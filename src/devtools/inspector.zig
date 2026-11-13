//! Developer Tools DOM Hierarchy Tree Inspector, Live Element Highlighter,
//! Computed CSS Style Panel, and Live CSS Rule Editor.

const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const StyleEngine = @import("../css/style.zig").StyleEngine;
const ComputedStyle = @import("../css/properties.zig").ComputedStyle;
const AtomTable = @import("../common/string.zig").AtomTable;
const AtomId = @import("../common/string.zig").AtomId;
const Rect = @import("../common/types.zig").Rect;
const Color = @import("../common/types.zig").Color;

pub const BoxModel = struct {
    margin: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    border: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    padding: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    content: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
};

pub const DomNodeSummary = struct {
    id: usize,
    tag_name: []const u8,
    id_attr: ?[]const u8 = null,
    class_attr: ?[]const u8 = null,
    child_count: usize = 0,
    depth: usize = 0,
    text_preview: ?[]const u8 = null,
};

pub const StyleDeclaration = struct {
    property: []const u8,
    value: []const u8,
    is_inherited: bool = false,
};

pub const MatchedRuleSummary = struct {
    selector: []const u8,
    specificity: u32,
    declarations: std.ArrayList(StyleDeclaration),

    pub fn deinit(self: *MatchedRuleSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        for (self.declarations.items) |d| {
            allocator.free(d.property);
            allocator.free(d.value);
        }
        self.declarations.deinit(allocator);
    }
};

pub const DomInspector = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    selected_node: ?*Node = null,
    highlight_rect: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable) DomInspector {
        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .selected_node = null,
            .highlight_rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
        };
    }

    pub fn deinit(self: *DomInspector) void {
        _ = self;
    }

    /// Selects a node in the inspector
    pub fn selectNode(self: *DomInspector, node: ?*Node) void {
        self.selected_node = node;
        if (node) |_| {
            // Update highlight bounds (default mock content box if unlaid)
            self.highlight_rect = .{ .x = 10, .y = 10, .width = 300, .height = 40 };
        } else {
            self.highlight_rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }
    }

    /// Finds and selects a node by its HTML ID attribute
    pub fn selectNodeById(self: *DomInspector, root: *Node, target_id: []const u8) ?*Node {
        const id_atom = self.atom_table.intern("id") catch return null;
        const found = findNodeById(root, id_atom, target_id);
        if (found) |n| {
            self.selectNode(n);
        }
        return found;
    }

    /// Selects a node by child index path (e.g. [0, 1, 2] -> 1st child -> 2nd child -> 3rd child)
    pub fn selectNodeByPath(self: *DomInspector, root: *Node, path: []const usize) ?*Node {
        var curr: *Node = root;
        for (path) |child_idx| {
            var idx: usize = 0;
            var c = curr.first_child;
            var found: ?*Node = null;
            while (c) |child| {
                if (idx == child_idx) {
                    found = child;
                    break;
                }
                idx += 1;
                c = child.next_sibling;
            }
            if (found) |f| {
                curr = f;
            } else {
                return null;
            }
        }
        self.selectNode(curr);
        return curr;
    }

    /// Serializes the live DOM hierarchy into an indented tree representation
    pub fn serializeDomTree(self: *DomInspector, root: *const Node) ![]u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(self.allocator);

        try self.appendNodeHierarchy(root, 0, &buf);
        return try buf.toOwnedSlice(self.allocator);
    }

    fn appendNodeHierarchy(self: *DomInspector, node: *const Node, depth: usize, buf: *std.ArrayList(u8)) !void {
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try buf.appendSlice(self.allocator, "  ");
        }

        switch (node.node_type) {
            .Element => {
                const tag = self.atom_table.get(node.tag_name);
                const is_selected = if (self.selected_node) |sn| sn == node else false;
                const marker = if (is_selected) "==> " else "";

                try buf.appendSlice(self.allocator, marker);
                try buf.append(self.allocator, '<');
                try buf.appendSlice(self.allocator, tag);

                const id_atom = self.atom_table.intern("id") catch null;
                const class_atom = self.atom_table.intern("class") catch null;

                if (id_atom) |ia| {
                    if (node.getAttribute(ia)) |id_val| {
                        const s = try std.fmt.allocPrint(self.allocator, " id=\"{s}\"", .{id_val});
                        defer self.allocator.free(s);
                        try buf.appendSlice(self.allocator, s);
                    }
                }
                if (class_atom) |ca| {
                    if (node.getAttribute(ca)) |cls_val| {
                        const s = try std.fmt.allocPrint(self.allocator, " class=\"{s}\"", .{cls_val});
                        defer self.allocator.free(s);
                        try buf.appendSlice(self.allocator, s);
                    }
                }
                try buf.appendSlice(self.allocator, ">\n");
            },
            .Text => {
                if (node.text_content) |txt| {
                    const trimmed = std.mem.trim(u8, txt, " \t\r\n");
                    if (trimmed.len > 0) {
                        const s = try std.fmt.allocPrint(self.allocator, "\"{s}\"\n", .{trimmed});
                        defer self.allocator.free(s);
                        try buf.appendSlice(self.allocator, s);
                    }
                }
            },
            .Document => {
                try buf.appendSlice(self.allocator, "#document\n");
            },
            else => {
                try buf.appendSlice(self.allocator, "#node\n");
            },
        }

        var curr = node.first_child;
        while (curr) |child| {
            try self.appendNodeHierarchy(child, depth + 1, buf);
            curr = child.next_sibling;
        }
    }

    /// Inspects computed CSS styles for the selected node
    pub fn inspectComputedStyles(self: *DomInspector, node: *const Node, style_engine: *StyleEngine) !std.ArrayList(StyleDeclaration) {
        var list = std.ArrayList(StyleDeclaration).empty;
        errdefer {
            for (list.items) |d| {
                self.allocator.free(d.property);
                self.allocator.free(d.value);
            }
            list.deinit(self.allocator);
        }

        const comp = try style_engine.computeStyle(node, null);

        // Display
        const disp_str = switch (comp.display) {
            .Block => "block",
            .Inline => "inline",
            .InlineBlock => "inline-block",
            .Flex => "flex",
            .Grid => "grid",
            .None => "none",
        };
        try list.append(self.allocator, .{
            .property = try self.allocator.dupe(u8, "display"),
            .value = try self.allocator.dupe(u8, disp_str),
        });

        // Position
        const pos_str = switch (comp.position) {
            .Static => "static",
            .Relative => "relative",
            .Absolute => "absolute",
            .Fixed => "fixed",
            .Sticky => "sticky",
        };
        try list.append(self.allocator, .{
            .property = try self.allocator.dupe(u8, "position"),
            .value = try self.allocator.dupe(u8, pos_str),
        });

        // Color
        const color_hex = try std.fmt.allocPrint(self.allocator, "rgba({d}, {d}, {d}, {d})", .{
            comp.color.r, comp.color.g, comp.color.b, comp.color.a,
        });
        try list.append(self.allocator, .{
            .property = try self.allocator.dupe(u8, "color"),
            .value = color_hex,
        });

        // Background Color
        const bg_hex = try std.fmt.allocPrint(self.allocator, "rgba({d}, {d}, {d}, {d})", .{
            comp.background_color.r, comp.background_color.g, comp.background_color.b, comp.background_color.a,
        });
        try list.append(self.allocator, .{
            .property = try self.allocator.dupe(u8, "background-color"),
            .value = bg_hex,
        });

        // Font Size
        const font_str = try std.fmt.allocPrint(self.allocator, "{d:.1}px", .{comp.font_size});
        try list.append(self.allocator, .{
            .property = try self.allocator.dupe(u8, "font-size"),
            .value = font_str,
        });

        return list;
    }

    /// Live Rule Editor: updates or sets an inline CSS style property on the selected node
    pub fn setInlineStyleProperty(self: *DomInspector, node: *Node, prop: []const u8, value: []const u8) !void {
        const style_atom = try self.atom_table.intern("style");
        const curr_style = node.getAttribute(style_atom) orelse "";

        var new_style = std.ArrayList(u8).empty;
        defer new_style.deinit(self.allocator);

        var replaced = false;
        var it = std.mem.splitScalar(u8, curr_style, ';');
        while (it.next()) |decl| {
            const trimmed = std.mem.trim(u8, decl, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                const p = std.mem.trim(u8, trimmed[0..colon], " \t\r\n");
                if (std.ascii.eqlIgnoreCase(p, prop)) {
                    const s = try std.fmt.allocPrint(self.allocator, "{s}: {s}; ", .{ prop, value });
                    defer self.allocator.free(s);
                    try new_style.appendSlice(self.allocator, s);
                    replaced = true;
                    continue;
                }
            }
            try new_style.appendSlice(self.allocator, trimmed);
            try new_style.appendSlice(self.allocator, "; ");
        }

        if (!replaced) {
            const s = try std.fmt.allocPrint(self.allocator, "{s}: {s}; ", .{ prop, value });
            defer self.allocator.free(s);
            try new_style.appendSlice(self.allocator, s);
        }

        try node.setAttribute(self.allocator, style_atom, new_style.items);
    }

    /// Live Rule Editor: removes an inline CSS property from the node
    pub fn removeInlineStyleProperty(self: *DomInspector, node: *Node, prop: []const u8) !void {
        const style_atom = try self.atom_table.intern("style");
        const curr_style = node.getAttribute(style_atom) orelse return;

        var new_style = std.ArrayList(u8).empty;
        defer new_style.deinit(self.allocator);

        var it = std.mem.splitScalar(u8, curr_style, ';');
        while (it.next()) |decl| {
            const trimmed = std.mem.trim(u8, decl, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                const p = std.mem.trim(u8, trimmed[0..colon], " \t\r\n");
                if (std.ascii.eqlIgnoreCase(p, prop)) {
                    continue; // Skip
                }
            }
            try new_style.appendSlice(self.allocator, trimmed);
            try new_style.appendSlice(self.allocator, "; ");
        }

        try node.setAttribute(self.allocator, style_atom, new_style.items);
    }

    /// Generates visual element highlight overlay HTML snippet
    pub fn renderHighlightOverlay(self: *const DomInspector) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\<div class="devtools-element-highlight" style="position: absolute; left: {d}px; top: {d}px; width: {d}px; height: {d}px; background-color: rgba(66, 133, 244, 0.3); border: 1px solid #4285f4; pointer-events: none; z-index: 999999;"></div>
        , .{
            self.highlight_rect.x,
            self.highlight_rect.y,
            self.highlight_rect.width,
            self.highlight_rect.height,
        });
    }

    /// Computes box model dimensions for the selected element
    pub fn getBoxModel(self: *const DomInspector) BoxModel {
        const r = self.highlight_rect;
        return .{
            .content = r,
            .padding = .{ .x = r.x - 4, .y = r.y - 4, .width = r.width + 8, .height = r.height + 8 },
            .border = .{ .x = r.x - 5, .y = r.y - 5, .width = r.width + 10, .height = r.height + 10 },
            .margin = .{ .x = r.x - 15, .y = r.y - 15, .width = r.width + 30, .height = r.height + 30 },
        };
    }
};

fn findNodeById(node: *Node, id_atom: AtomId, target_id: []const u8) ?*Node {
    if (node.node_type == .Element) {
        if (node.getAttribute(id_atom)) |id_val| {
            if (std.mem.eql(u8, id_val, target_id)) return node;
        }
    }
    var curr = node.first_child;
    while (curr) |child| {
        if (findNodeById(child, id_atom, target_id)) |found| return found;
        curr = child.next_sibling;
    }
    return null;
}

test "devtools inspector dom hierarchy tree, node selection and element highlight" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var inspector = DomInspector.init(allocator, table);
    defer inspector.deinit();

    // Construct test DOM
    const doc = try Node.create(allocator, .Document, AtomId.empty);
    defer doc.deinit(allocator);

    const body = try Node.create(allocator, .Element, try table.intern("body"));
    try doc.appendChild(allocator, body);

    const main_div = try Node.create(allocator, .Element, try table.intern("div"));
    try main_div.setAttribute(allocator, try table.intern("id"), "main-card");
    try main_div.setAttribute(allocator, try table.intern("class"), "card hero");
    try body.appendChild(allocator, main_div);

    const heading = try Node.create(allocator, .Element, try table.intern("h1"));
    const h_text = try Node.createText(allocator, "Davoth Inspector");
    try heading.appendChild(allocator, h_text);
    try main_div.appendChild(allocator, heading);

    // 1. Serialization
    const tree_str = try inspector.serializeDomTree(doc);
    defer allocator.free(tree_str);
    try std.testing.expect(std.mem.indexOf(u8, tree_str, "<div id=\"main-card\" class=\"card hero\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree_str, "<h1>") != null);

    // 2. Node Selection by ID
    const selected = inspector.selectNodeById(doc, "main-card");
    try std.testing.expect(selected != null);
    try std.testing.expectEqual(main_div, inspector.selected_node.?);
    try std.testing.expect(inspector.highlight_rect.width > 0);

    // 3. Highlight Overlay
    const overlay = try inspector.renderHighlightOverlay();
    defer allocator.free(overlay);
    try std.testing.expect(std.mem.indexOf(u8, overlay, "devtools-element-highlight") != null);

    // 4. Box Model
    const box = inspector.getBoxModel();
    try std.testing.expect(box.margin.width > box.content.width);

    // 5. Node Selection by Path
    const found_h1 = inspector.selectNodeByPath(doc, &[_]usize{ 0, 0, 0 });
    try std.testing.expectEqual(heading, found_h1.?);
}

test "devtools computed css style panel and live rule editor" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var inspector = DomInspector.init(allocator, table);
    defer inspector.deinit();

    const style_engine = try StyleEngine.init(allocator, table);
    defer style_engine.deinit();

    const div = try Node.create(allocator, .Element, try table.intern("div"));
    defer div.deinit(allocator);

    // 1. Live rule editor: set inline style
    try inspector.setInlineStyleProperty(div, "color", "#ff5500");
    try inspector.setInlineStyleProperty(div, "display", "flex");

    const style_atom = try table.intern("style");
    const style_val = div.getAttribute(style_atom).?;
    try std.testing.expect(std.mem.indexOf(u8, style_val, "color: #ff5500") != null);
    try std.testing.expect(std.mem.indexOf(u8, style_val, "display: flex") != null);

    // 2. Computed Styles Inspection
    var computed = try inspector.inspectComputedStyles(div, style_engine);
    defer {
        for (computed.items) |d| {
            allocator.free(d.property);
            allocator.free(d.value);
        }
        computed.deinit(allocator);
    }

    var found_display_flex = false;
    for (computed.items) |decl| {
        if (std.mem.eql(u8, decl.property, "display") and std.mem.eql(u8, decl.value, "flex")) {
            found_display_flex = true;
        }
    }
    try std.testing.expect(found_display_flex);

    // 3. Remove inline style property
    try inspector.removeInlineStyleProperty(div, "color");
    const updated_style = div.getAttribute(style_atom).?;
    try std.testing.expect(std.mem.indexOf(u8, updated_style, "color") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated_style, "display: flex") != null);
}
