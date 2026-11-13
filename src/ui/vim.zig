//! Vim modal keyboard navigation controller, link hint generator, and command engine.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Node = @import("../dom/node.zig").Node;
const LayoutBox = @import("../layout/box.zig").LayoutBox;
const AtomTable = @import("../common/string.zig").AtomTable;

pub const VimMode = enum {
    Normal,
    Insert,
    Hint,
    Visual,
    Command,
    Find,
};

pub const VimActionType = enum {
    None,
    ScrollDown,
    ScrollUp,
    ScrollLeft,
    ScrollRight,
    HalfPageDown,
    HalfPageUp,
    ScrollTop,
    ScrollBottom,
    NewTab,
    CloseTab,
    ActivateTab,
    HistoryBack,
    HistoryForward,
    Reload,
    EnterInsertMode,
    EnterHintMode,
    EnterCommandMode,
    EnterFindMode,
    ExecuteCommand,
    ExecuteFind,
    FindNext,
    FindPrev,
    FollowHint,
    FocusElement,
};

pub const HintMarker = struct {
    label: [4]u8 = [_]u8{ 0, 0, 0, 0 },
    label_len: u8 = 0,
    node: ?*const Node = null,
    target_url: ?[]const u8 = null,
    is_input: bool = false,
    is_button: bool = false,
    bounds: Rect = Rect.zero,

    pub fn getLabel(self: *const HintMarker) []const u8 {
        return self.label[0..self.label_len];
    }
};

pub const VimAction = union(VimActionType) {
    None: void,
    ScrollDown: f32,
    ScrollUp: f32,
    ScrollLeft: f32,
    ScrollRight: f32,
    HalfPageDown: f32,
    HalfPageUp: f32,
    ScrollTop: void,
    ScrollBottom: void,
    NewTab: ?[]const u8,
    CloseTab: void,
    ActivateTab: usize,
    HistoryBack: void,
    HistoryForward: void,
    Reload: void,
    EnterInsertMode: void,
    EnterHintMode: bool, // true if opening in background/new tab (F), false if current tab (f)
    EnterCommandMode: void,
    EnterFindMode: void,
    ExecuteCommand: []const u8,
    ExecuteFind: []const u8,
    FindNext: void,
    FindPrev: void,
    FollowHint: struct {
        target_url: ?[]const u8,
        is_input: bool,
        node: ?*const Node,
        new_tab: bool,
    },
    FocusElement: *const Node,
};

pub const CandidateInteractive = struct {
    node: *const Node,
    url: ?[]const u8,
    is_input: bool,
    is_button: bool,
    bounds: Rect,
};

pub const VimController = struct {
    allocator: std.mem.Allocator,
    mode: VimMode = .Normal,
    scroll_offset_y: f32 = 0.0,
    scroll_offset_x: f32 = 0.0,
    scroll_step: f32 = 50.0,
    half_page_step: f32 = 350.0,
    max_scroll_y: f32 = 2500.0,
    viewport_height: f32 = 800.0,
    viewport_width: f32 = 1280.0,

    pending_char: ?u8 = null,
    hint_buffer: [8]u8 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    hint_len: usize = 0,
    hint_new_tab: bool = false,

    hints: std.ArrayList(HintMarker),

    command_buffer: [256]u8 = @splat(0),
    command_len: usize = 0,

    find_buffer: [128]u8 = @splat(0),
    find_len: usize = 0,
    last_find: [128]u8 = @splat(0),
    last_find_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) VimController {
        return .{
            .allocator = allocator,
            .mode = .Normal,
            .scroll_offset_y = 0.0,
            .scroll_offset_x = 0.0,
            .scroll_step = 50.0,
            .half_page_step = 350.0,
            .max_scroll_y = 2500.0,
            .viewport_height = 800.0,
            .viewport_width = 1280.0,
            .pending_char = null,
            .hint_buffer = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
            .hint_len = 0,
            .hint_new_tab = false,
            .hints = .empty,
            .command_buffer = @splat(0),
            .command_len = 0,
            .find_buffer = @splat(0),
            .find_len = 0,
            .last_find = @splat(0),
            .last_find_len = 0,
        };
    }

    pub fn deinit(self: *VimController) void {
        self.hints.deinit(self.allocator);
    }

    pub fn setScrollBounds(self: *VimController, max_y: f32, view_w: f32, view_h: f32) void {
        self.max_scroll_y = @max(0.0, max_y);
        self.viewport_width = view_w;
        self.viewport_height = view_h;
        self.half_page_step = @max(100.0, view_h / 2.0);
    }

    pub fn clearHints(self: *VimController) void {
        self.hints.clearRetainingCapacity();
        self.hint_len = 0;
    }

    /// Recursively indexes clickable/interactive elements from the DOM and Layout tree.
    pub fn generateHints(self: *VimController, document: *const Node, layout_root: ?*const LayoutBox, atom_table: *AtomTable) !void {
        self.clearHints();

        const a_atom = try atom_table.intern("a");
        const button_atom = try atom_table.intern("button");
        const input_atom = try atom_table.intern("input");
        const textarea_atom = try atom_table.intern("textarea");
        const select_atom = try atom_table.intern("select");
        const href_atom = try atom_table.intern("href");
        const onclick_atom = try atom_table.intern("onclick");
        const tabindex_atom = try atom_table.intern("tabindex");

        var candidates: std.ArrayList(CandidateInteractive) = .empty;
        defer candidates.deinit(self.allocator);

        try collectInteractiveNodes(
            self.allocator,
            document,
            layout_root,
            &candidates,
            a_atom,
            button_atom,
            input_atom,
            textarea_atom,
            select_atom,
            href_atom,
            onclick_atom,
            tabindex_atom,
        );

        if (candidates.items.len == 0) return;

        // Vimium home-row alphabet
        const alphabet = "sadfjklewcmpghuvion";
        const alpha_len = alphabet.len;

        for (candidates.items, 0..) |cand, i| {
            var marker = HintMarker{
                .node = cand.node,
                .target_url = cand.url,
                .is_input = cand.is_input,
                .is_button = cand.is_button,
                .bounds = cand.bounds,
            };

            if (candidates.items.len <= alpha_len) {
                marker.label[0] = alphabet[i];
                marker.label_len = 1;
            } else {
                const first_idx = i / alpha_len;
                const second_idx = i % alpha_len;
                marker.label[0] = alphabet[first_idx % alpha_len];
                marker.label[1] = alphabet[second_idx];
                marker.label_len = 2;
            }

            try self.hints.append(self.allocator, marker);
        }
    }

    /// Updates existing hint markers dynamically when DOM changes occur.
    pub fn updateHintsOnDomChange(self: *VimController, document: *const Node, layout_root: ?*const LayoutBox, atom_table: *AtomTable) !void {
        const saved_len = self.hint_len;
        const saved_buf = self.hint_buffer;
        try self.generateHints(document, layout_root, atom_table);
        self.hint_len = @min(saved_len, self.hint_buffer.len);
        self.hint_buffer = saved_buf;
    }

    /// Main modal key handler conforming to Vim navigation rules.
    pub fn handleKey(self: *VimController, key: u8) ?VimAction {
        switch (self.mode) {
            .Normal => return self.handleNormalKey(key),
            .Hint => return self.handleHintKey(key),
            .Insert => return self.handleInsertKey(key),
            .Visual => return self.handleVisualKey(key),
            .Command => return self.handleCommandKey(key),
            .Find => return self.handleFindKey(key),
        }
    }

    fn handleNormalKey(self: *VimController, key: u8) ?VimAction {
        // Multi-key sequences: 'gg'
        if (self.pending_char) |p| {
            self.pending_char = null;
            if (p == 'g' and key == 'g') {
                self.scroll_offset_y = 0.0;
                return .ScrollTop;
            }
        }

        switch (key) {
            // Scrolling
            'j' => {
                self.scroll_offset_y = @min(self.max_scroll_y, self.scroll_offset_y + self.scroll_step);
                return VimAction{ .ScrollDown = self.scroll_step };
            },
            'k' => {
                self.scroll_offset_y = @max(0.0, self.scroll_offset_y - self.scroll_step);
                return VimAction{ .ScrollUp = self.scroll_step };
            },
            'h' => {
                self.scroll_offset_x = @max(0.0, self.scroll_offset_x - self.scroll_step);
                return VimAction{ .ScrollLeft = self.scroll_step };
            },
            'l' => {
                self.scroll_offset_x += self.scroll_step;
                return VimAction{ .ScrollRight = self.scroll_step };
            },
            'd' => {
                self.scroll_offset_y = @min(self.max_scroll_y, self.scroll_offset_y + self.half_page_step);
                return VimAction{ .HalfPageDown = self.half_page_step };
            },
            'u' => {
                self.scroll_offset_y = @max(0.0, self.scroll_offset_y - self.half_page_step);
                return VimAction{ .HalfPageUp = self.half_page_step };
            },
            'G' => {
                self.scroll_offset_y = self.max_scroll_y;
                return .ScrollBottom;
            },
            'g' => {
                self.pending_char = 'g';
                return null;
            },

            // Tabs & Navigation
            't' => {
                return VimAction{ .NewTab = null };
            },
            'x' => {
                return .CloseTab;
            },
            'r' => {
                return .Reload;
            },
            'H' => {
                return .HistoryBack;
            },
            'L' => {
                return .HistoryForward;
            },

            // Follow / Hint Mode
            'f' => {
                self.mode = .Hint;
                self.hint_len = 0;
                self.hint_new_tab = false;
                return VimAction{ .EnterHintMode = false };
            },
            'F' => {
                self.mode = .Hint;
                self.hint_len = 0;
                self.hint_new_tab = true;
                return VimAction{ .EnterHintMode = true };
            },

            // Mode Switching
            'i' => {
                self.mode = .Insert;
                return .EnterInsertMode;
            },
            'v' => {
                self.mode = .Visual;
                return null;
            },
            ':' => {
                self.mode = .Command;
                self.command_len = 0;
                return .EnterCommandMode;
            },
            '/' => {
                self.mode = .Find;
                self.find_len = 0;
                return .EnterFindMode;
            },
            'n' => {
                return .FindNext;
            },
            'N' => {
                return .FindPrev;
            },

            27 => { // Escape
                self.pending_char = null;
                return null;
            },

            else => return null,
        }
    }

    fn handleHintKey(self: *VimController, key: u8) ?VimAction {
        if (key == 27) { // Escape
            self.mode = .Normal;
            self.hint_len = 0;
            return null;
        }

        if (key == 8 or key == 127) { // Backspace
            if (self.hint_len > 0) {
                self.hint_len -= 1;
            } else {
                self.mode = .Normal;
            }
            return null;
        }

        if (std.ascii.isAlphabetic(key)) {
            const lower_key = std.ascii.toLower(key);
            if (self.hint_len < self.hint_buffer.len) {
                self.hint_buffer[self.hint_len] = lower_key;
                self.hint_len += 1;
            }

            const current_input = self.hint_buffer[0..self.hint_len];

            // Count prefix matches and exact matches
            var exact_marker: ?HintMarker = null;
            var prefix_match_count: usize = 0;

            for (self.hints.items) |marker| {
                const lbl = marker.getLabel();
                if (std.mem.startsWith(u8, lbl, current_input)) {
                    prefix_match_count += 1;
                    if (std.mem.eql(u8, lbl, current_input)) {
                        exact_marker = marker;
                    }
                }
            }

            // If we have an exact match and no longer ambiguous hints, activate!
            if (exact_marker) |m| {
                if (prefix_match_count == 1 or m.label_len == self.hint_len) {
                    self.mode = .Normal;
                    self.hint_len = 0;

                    if (m.is_input and m.node != null) {
                        self.mode = .Insert;
                        return VimAction{ .FocusElement = m.node.? };
                    }

                    return VimAction{
                        .FollowHint = .{
                            .target_url = m.target_url,
                            .is_input = m.is_input,
                            .node = m.node,
                            .new_tab = self.hint_new_tab,
                        },
                    };
                }
            }

            // If no hints match prefix, reset or sound warning
            if (prefix_match_count == 0) {
                self.hint_len = 0;
            }
        }

        return null;
    }

    fn handleInsertKey(self: *VimController, key: u8) ?VimAction {
        if (key == 27) { // Escape returns to Normal mode
            self.mode = .Normal;
            return null;
        }
        return null;
    }

    fn handleVisualKey(self: *VimController, key: u8) ?VimAction {
        if (key == 27 or key == 'v') { // Escape or 'v' returns to Normal mode
            self.mode = .Normal;
            return null;
        }
        return null;
    }

    fn handleCommandKey(self: *VimController, key: u8) ?VimAction {
        if (key == 27) { // Escape
            self.mode = .Normal;
            self.command_len = 0;
            return null;
        }

        if (key == '\r' or key == '\n') { // Enter executes command
            self.mode = .Normal;
            const cmd = self.command_buffer[0..self.command_len];
            return self.parseAndExecuteCommand(cmd);
        }

        if (key == 8 or key == 127) { // Backspace
            if (self.command_len > 0) {
                self.command_len -= 1;
            } else {
                self.mode = .Normal;
            }
            return null;
        }

        if (self.command_len < self.command_buffer.len and std.ascii.isPrint(key)) {
            self.command_buffer[self.command_len] = key;
            self.command_len += 1;
        }

        return null;
    }

    fn handleFindKey(self: *VimController, key: u8) ?VimAction {
        if (key == 27) { // Escape
            self.mode = .Normal;
            self.find_len = 0;
            return null;
        }

        if (key == '\r' or key == '\n') { // Enter confirms search query
            self.mode = .Normal;
            if (self.find_len > 0) {
                @memcpy(self.last_find[0..self.find_len], self.find_buffer[0..self.find_len]);
                self.last_find_len = self.find_len;
                return VimAction{ .ExecuteFind = self.last_find[0..self.last_find_len] };
            }
            return null;
        }

        if (key == 8 or key == 127) { // Backspace
            if (self.find_len > 0) {
                self.find_len -= 1;
            } else {
                self.mode = .Normal;
            }
            return null;
        }

        if (self.find_len < self.find_buffer.len and std.ascii.isPrint(key)) {
            self.find_buffer[self.find_len] = key;
            self.find_len += 1;
        }

        return null;
    }

    fn parseAndExecuteCommand(self: *VimController, cmd: []const u8) VimAction {
        const trimmed = std.mem.trim(u8, cmd, " ");
        if (trimmed.len == 0) return .None;

        if (std.mem.startsWith(u8, trimmed, "open ") or std.mem.startsWith(u8, trimmed, "o ")) {
            const url_part = if (std.mem.startsWith(u8, trimmed, "open ")) trimmed[5..] else trimmed[2..];
            return VimAction{ .ExecuteCommand = std.mem.trim(u8, url_part, " ") };
        }

        if (std.mem.startsWith(u8, trimmed, "tabnew") or std.mem.startsWith(u8, trimmed, "t")) {
            var url: ?[]const u8 = null;
            if (std.mem.startsWith(u8, trimmed, "tabnew ")) {
                url = std.mem.trim(u8, trimmed[7..], " ");
            } else if (std.mem.startsWith(u8, trimmed, "t ")) {
                url = std.mem.trim(u8, trimmed[2..], " ");
            }
            return VimAction{ .NewTab = url };
        }

        if (std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "tabclose") or std.mem.eql(u8, trimmed, "bdelete")) {
            return .CloseTab;
        }

        if (std.mem.eql(u8, trimmed, "r") or std.mem.eql(u8, trimmed, "reload")) {
            return .Reload;
        }

        if (std.mem.startsWith(u8, trimmed, "b ") or std.mem.startsWith(u8, trimmed, "buffer ")) {
            const num_str = if (std.mem.startsWith(u8, trimmed, "b ")) trimmed[2..] else trimmed[7..];
            const idx = std.fmt.parseInt(usize, std.mem.trim(u8, num_str, " "), 10) catch 1;
            return VimAction{ .ActivateTab = if (idx > 0) idx - 1 else 0 };
        }

        if (std.mem.startsWith(u8, trimmed, "find ")) {
            return VimAction{ .ExecuteFind = std.mem.trim(u8, trimmed[5..], " ") };
        }

        _ = self;
        return VimAction{ .ExecuteCommand = trimmed };
    }
};

fn collectInteractiveNodes(
    allocator: std.mem.Allocator,
    node: *const Node,
    layout_root: ?*const LayoutBox,
    candidates: *std.ArrayList(CandidateInteractive),
    a_atom: @import("../common/string.zig").AtomId,
    button_atom: @import("../common/string.zig").AtomId,
    input_atom: @import("../common/string.zig").AtomId,
    textarea_atom: @import("../common/string.zig").AtomId,
    select_atom: @import("../common/string.zig").AtomId,
    href_atom: @import("../common/string.zig").AtomId,
    onclick_atom: @import("../common/string.zig").AtomId,
    tabindex_atom: @import("../common/string.zig").AtomId,
) !void {
    if (node.node_type == .Element) {
        var is_interactive = false;
        var target_url: ?[]const u8 = null;
        var is_input = false;
        var is_button = false;

        if (node.tag_name == a_atom) {
            is_interactive = true;
            target_url = node.getAttribute(href_atom);
        } else if (node.tag_name == button_atom) {
            is_interactive = true;
            is_button = true;
        } else if (node.tag_name == input_atom or node.tag_name == textarea_atom or node.tag_name == select_atom) {
            is_interactive = true;
            is_input = true;
        } else if (node.getAttribute(onclick_atom) != null or node.getAttribute(tabindex_atom) != null) {
            is_interactive = true;
        }

        if (is_interactive) {
            var box_rect = Rect.zero;
            if (layout_root) |lr| {
                if (findBoxForNode(lr, node)) |b| {
                    box_rect = b.dimensions.borderBox();
                }
            }

            try candidates.append(allocator, .{
                .node = node,
                .url = target_url,
                .is_input = is_input,
                .is_button = is_button,
                .bounds = box_rect,
            });
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        try collectInteractiveNodes(
            allocator,
            child,
            layout_root,
            candidates,
            a_atom,
            button_atom,
            input_atom,
            textarea_atom,
            select_atom,
            href_atom,
            onclick_atom,
            tabindex_atom,
        );
        curr = child.next_sibling;
    }
}

fn findBoxForNode(box: *const LayoutBox, target_node: *const Node) ?*const LayoutBox {
    if (box.node == target_node) return box;
    for (box.children.items) |child| {
        if (findBoxForNode(child, target_node)) |found| return found;
    }
    return null;
}

/// Backwards compatibility struct for existing callers
pub const VimNavigator = struct {
    mode: VimMode = .Normal,
    scroll_offset: f32 = 0.0,
    hint_buffer: [4]u8 = undefined,
    hint_len: usize = 0,

    pub fn handleKey(self: *VimNavigator, key: u8) ?enum { ScrollDown, ScrollUp, ScrollTop, ScrollBottom, CloseTab, NewTab, EnterHintMode } {
        if (self.mode == .Normal) {
            switch (key) {
                'j' => {
                    self.scroll_offset += 50.0;
                    return .ScrollDown;
                },
                'k' => {
                    self.scroll_offset = @max(0.0, self.scroll_offset - 50.0);
                    return .ScrollUp;
                },
                'd' => return .CloseTab,
                't' => return .NewTab,
                'f' => {
                    self.mode = .Hint;
                    self.hint_len = 0;
                    return .EnterHintMode;
                },
                'i' => {
                    self.mode = .Insert;
                    return null;
                },
                else => return null,
            }
        } else if (self.mode == .Hint) {
            if (key == 27) { // Escape
                self.mode = .Normal;
            }
        }
        return null;
    }
};

test "vim navigator key handling backwards compatibility" {
    var vim = VimNavigator{};
    try std.testing.expectEqual(VimMode.Normal, vim.mode);

    const act = vim.handleKey('j');
    try std.testing.expect(act != null);
    try std.testing.expectEqual(@as(f32, 50.0), vim.scroll_offset);
}

test "vim controller scrolling, half page, and gg sequence" {
    const allocator = std.testing.allocator;
    var vim = VimController.init(allocator);
    defer vim.deinit();

    vim.setScrollBounds(2000.0, 1024.0, 600.0);

    // j: scroll down
    const act_j = vim.handleKey('j');
    try std.testing.expect(act_j != null);
    try std.testing.expectEqual(@as(f32, 50.0), vim.scroll_offset_y);

    // d: half page down (300px)
    const act_d = vim.handleKey('d');
    try std.testing.expect(act_d != null);
    try std.testing.expectEqual(@as(f32, 350.0), vim.scroll_offset_y);

    // u: half page up
    const act_u = vim.handleKey('u');
    try std.testing.expect(act_u != null);
    try std.testing.expectEqual(@as(f32, 50.0), vim.scroll_offset_y);

    // G: scroll bottom
    const act_g_upper = vim.handleKey('G');
    try std.testing.expect(act_g_upper != null);
    try std.testing.expectEqual(@as(f32, 2000.0), vim.scroll_offset_y);

    // gg: scroll top
    _ = vim.handleKey('g');
    const act_gg = vim.handleKey('g');
    try std.testing.expect(act_gg != null);
    try std.testing.expectEqual(@as(f32, 0.0), vim.scroll_offset_y);
}

test "vim controller command mode parsing" {
    const allocator = std.testing.allocator;
    var vim = VimController.init(allocator);
    defer vim.deinit();

    // Enter command mode with ':'
    const enter_act = vim.handleKey(':');
    try std.testing.expect(enter_act != null);
    try std.testing.expectEqual(VimMode.Command, vim.mode);

    // Type "tabnew https://kernel.org" and press Enter
    const cmd_str = "tabnew https://kernel.org\n";
    var final_act: ?VimAction = null;
    for (cmd_str) |c| {
        final_act = vim.handleKey(c);
    }

    try std.testing.expect(final_act != null);
    try std.testing.expectEqual(VimMode.Normal, vim.mode);
    switch (final_act.?) {
        .NewTab => |opt_url| {
            try std.testing.expect(opt_url != null);
            try std.testing.expectEqualStrings("https://kernel.org", opt_url.?);
        },
        else => unreachable,
    }
}

test "vim controller link hint generation and matching" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var vim = VimController.init(allocator);
    defer vim.deinit();

    // Create a mock DOM tree with interactive elements
    const body = try Node.create(allocator, .Element, try table.intern("body"));
    defer body.deinit(allocator);

    const a1 = try Node.create(allocator, .Element, try table.intern("a"));
    try a1.setAttribute(allocator, try table.intern("href"), "https://davoth.org/about");
    try body.appendChild(allocator, a1);

    const btn = try Node.create(allocator, .Element, try table.intern("button"));
    try body.appendChild(allocator, btn);

    const inp = try Node.create(allocator, .Element, try table.intern("input"));
    try body.appendChild(allocator, inp);

    // Generate hints
    try vim.generateHints(body, null, table);
    try std.testing.expectEqual(@as(usize, 3), vim.hints.items.len);

    const hint0 = vim.hints.items[0];
    try std.testing.expectEqualStrings("s", hint0.getLabel());
    try std.testing.expectEqualStrings("https://davoth.org/about", hint0.target_url.?);

    // Activate hint mode with 'f'
    _ = vim.handleKey('f');
    try std.testing.expectEqual(VimMode.Hint, vim.mode);

    // Press 's' to activate first link
    const hit_act = vim.handleKey('s');
    try std.testing.expect(hit_act != null);
    try std.testing.expectEqual(VimMode.Normal, vim.mode);

    switch (hit_act.?) {
        .FollowHint => |data| {
            try std.testing.expectEqualStrings("https://davoth.org/about", data.target_url.?);
            try std.testing.expect(!data.new_tab);
        },
        else => unreachable,
    }
}

test "vim controller dynamic DOM changes hint re-indexing" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var vim = VimController.init(allocator);
    defer vim.deinit();

    const body = try Node.create(allocator, .Element, try table.intern("body"));
    defer body.deinit(allocator);

    const a1 = try Node.create(allocator, .Element, try table.intern("a"));
    try a1.setAttribute(allocator, try table.intern("href"), "https://1.com");
    try body.appendChild(allocator, a1);

    try vim.generateHints(body, null, table);
    try std.testing.expectEqual(@as(usize, 1), vim.hints.items.len);

    // Dynamically insert another element
    const a2 = try Node.create(allocator, .Element, try table.intern("a"));
    try a2.setAttribute(allocator, try table.intern("href"), "https://2.com");
    try body.appendChild(allocator, a2);

    // Update hints on dynamic DOM change
    try vim.updateHintsOnDomChange(body, null, table);
    try std.testing.expectEqual(@as(usize, 2), vim.hints.items.len);
    try std.testing.expectEqualStrings("https://2.com", vim.hints.items[1].target_url.?);
}
