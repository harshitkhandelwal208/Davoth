//! Complete DOM Core node model with hierarchy traversal, attributes, and query methods.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const NodeType = enum(u8) {
    Document = 9,
    Element = 1,
    Text = 3,
    Comment = 8,
    DocumentFragment = 11,
};

pub const Attribute = struct {
    name: AtomId,
    value: []const u8,
};

pub const EventListener = struct {
    event_type: AtomId,
    callback: *const fn (ctx: *anyopaque, event: *anyopaque) void,
    ctx: *anyopaque,
    use_capture: bool = false,
};

pub const DOMTokenList = struct {
    node: *Node,
    table: *AtomTable,

    pub fn value(self: DOMTokenList) []const u8 {
        const class_atom = self.table.intern("class") catch return "";
        return self.node.getAttribute(class_atom) orelse "";
    }

    pub fn contains(self: DOMTokenList, token: []const u8) bool {
        const cur = self.value();
        if (cur.len == 0) return false;
        var it = std.mem.tokenizeScalar(u8, cur, ' ');
        while (it.next()) |item| {
            if (std.mem.eql(u8, item, token)) return true;
        }
        return false;
    }

    pub fn add(self: DOMTokenList, allocator: std.mem.Allocator, token: []const u8) !void {
        if (self.contains(token)) return;
        const cur = self.value();
        const class_atom = try self.table.intern("class");
        if (cur.len == 0) {
            try self.node.setAttribute(allocator, class_atom, token);
        } else {
            const joined = try std.fmt.allocPrint(allocator, "{s} {s}", .{ cur, token });
            defer allocator.free(joined);
            try self.node.setAttribute(allocator, class_atom, joined);
        }
    }

    pub fn remove(self: DOMTokenList, allocator: std.mem.Allocator, token: []const u8) !void {
        if (!self.contains(token)) return;
        const cur = self.value();
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        var it = std.mem.tokenizeScalar(u8, cur, ' ');
        while (it.next()) |item| {
            if (std.mem.eql(u8, item, token)) continue;
            if (out.items.len > 0) try out.append(allocator, ' ');
            try out.appendSlice(allocator, item);
        }

        const class_atom = try self.table.intern("class");
        if (out.items.len == 0) {
            _ = self.node.removeAttribute(allocator, class_atom);
        } else {
            try self.node.setAttribute(allocator, class_atom, out.items);
        }
    }

    pub fn toggle(self: DOMTokenList, allocator: std.mem.Allocator, token: []const u8) !bool {
        if (self.contains(token)) {
            try self.remove(allocator, token);
            return false;
        } else {
            try self.add(allocator, token);
            return true;
        }
    }

    pub fn replace(self: DOMTokenList, allocator: std.mem.Allocator, old_token: []const u8, new_token: []const u8) !bool {
        if (!self.contains(old_token)) return false;
        try self.remove(allocator, old_token);
        try self.add(allocator, new_token);
        return true;
    }
};

pub const Node = struct {
    node_type: NodeType,
    tag_name: AtomId = AtomId.empty,
    text_content: ?[]const u8 = null,

    // Hierarchy pointers
    parent_node: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    next_sibling: ?*Node = null,
    prev_sibling: ?*Node = null,

    // Element attributes
    attributes: std.ArrayList(Attribute),
    shadow_root: ?*Node = null,
    listeners: std.ArrayList(EventListener),

    pub fn create(allocator: std.mem.Allocator, node_type: NodeType, tag_name: AtomId) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .node_type = node_type,
            .tag_name = tag_name,
            .text_content = null,
            .parent_node = null,
            .first_child = null,
            .last_child = null,
            .next_sibling = null,
            .prev_sibling = null,
            .attributes = .empty,
            .shadow_root = null,
            .listeners = .empty,
        };
        SubsystemMemoryTracker.global.recordAlloc(.DOM, @sizeOf(Node));
        return node;
    }

    pub fn createText(allocator: std.mem.Allocator, text: []const u8) !*Node {
        const node = try create(allocator, .Text, AtomId.empty);
        node.text_content = try allocator.dupe(u8, text);
        SubsystemMemoryTracker.global.recordAlloc(.DOM, text.len);
        return node;
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        var curr = self.first_child;
        while (curr) |child| {
            const next = child.next_sibling;
            child.deinit(allocator);
            curr = next;
        }

        if (self.text_content) |txt| {
            allocator.free(txt);
            SubsystemMemoryTracker.global.recordFree(.DOM, txt.len);
        }

        for (self.attributes.items) |attr| {
            allocator.free(attr.value);
            SubsystemMemoryTracker.global.recordFree(.DOM, attr.value.len);
        }
        self.attributes.deinit(allocator);
        self.listeners.deinit(allocator);

        if (self.shadow_root) |sr| {
            sr.deinit(allocator);
        }

        SubsystemMemoryTracker.global.recordFree(.DOM, @sizeOf(Node));
        allocator.destroy(self);
    }

    pub fn appendChild(self: *Node, allocator: std.mem.Allocator, child: *Node) !void {
        _ = allocator;
        if (child.parent_node) |p| {
            p.removeChild(child);
        }

        child.parent_node = self;
        child.prev_sibling = self.last_child;
        child.next_sibling = null;

        if (self.last_child) |last| {
            last.next_sibling = child;
        } else {
            self.first_child = child;
        }
        self.last_child = child;
    }

    pub fn removeChild(self: *Node, child: *Node) void {
        if (child.parent_node != self) return;

        if (child.prev_sibling) |prev| {
            prev.next_sibling = child.next_sibling;
        } else {
            self.first_child = child.next_sibling;
        }

        if (child.next_sibling) |next| {
            next.prev_sibling = child.prev_sibling;
        } else {
            self.last_child = child.prev_sibling;
        }

        child.parent_node = null;
        child.prev_sibling = null;
        child.next_sibling = null;
    }

    pub fn insertBefore(self: *Node, allocator: std.mem.Allocator, new_child: *Node, ref_child: ?*Node) !void {
        if (ref_child == null) {
            return self.appendChild(allocator, new_child);
        }
        const ref = ref_child.?;
        if (ref.parent_node != self) {
            return error.NotFound;
        }

        if (new_child.parent_node) |p| {
            p.removeChild(new_child);
        }

        new_child.parent_node = self;
        new_child.next_sibling = ref;
        new_child.prev_sibling = ref.prev_sibling;

        if (ref.prev_sibling) |prev| {
            prev.next_sibling = new_child;
        } else {
            self.first_child = new_child;
        }
        ref.prev_sibling = new_child;
    }

    pub fn replaceChild(self: *Node, allocator: std.mem.Allocator, new_child: *Node, old_child: *Node) !void {
        _ = allocator;
        if (old_child.parent_node != self) {
            return error.NotFound;
        }

        if (new_child.parent_node) |p| {
            p.removeChild(new_child);
        }

        new_child.parent_node = self;
        new_child.next_sibling = old_child.next_sibling;
        new_child.prev_sibling = old_child.prev_sibling;

        if (old_child.prev_sibling) |prev| {
            prev.next_sibling = new_child;
        } else {
            self.first_child = new_child;
        }

        if (old_child.next_sibling) |next| {
            next.prev_sibling = new_child;
        } else {
            self.last_child = new_child;
        }

        old_child.parent_node = null;
        old_child.prev_sibling = null;
        old_child.next_sibling = null;
    }

    pub fn setAttribute(self: *Node, allocator: std.mem.Allocator, name: AtomId, value: []const u8) !void {
        for (self.attributes.items) |*attr| {
            if (attr.name == name) {
                allocator.free(attr.value);
                attr.value = try allocator.dupe(u8, value);
                return;
            }
        }
        const val_copy = try allocator.dupe(u8, value);
        SubsystemMemoryTracker.global.recordAlloc(.DOM, val_copy.len);
        try self.attributes.append(allocator, .{ .name = name, .value = val_copy });
    }

    pub fn getAttribute(self: *const Node, name: AtomId) ?[]const u8 {
        for (self.attributes.items) |attr| {
            if (attr.name == name) return attr.value;
        }
        return null;
    }

    pub fn getElementById(self: *Node, table: *AtomTable, id: []const u8) ?*Node {
        const id_atom = table.intern("id") catch return null;
        return self.findFirst(id_atom, id);
    }

    pub fn addEventListener(
        self: *Node,
        allocator: std.mem.Allocator,
        event_type: AtomId,
        callback: *const fn (ctx: *anyopaque, event: *anyopaque) void,
        ctx: *anyopaque,
        use_capture: bool,
    ) !void {
        try self.listeners.append(allocator, .{
            .event_type = event_type,
            .callback = callback,
            .ctx = ctx,
            .use_capture = use_capture,
        });
    }

    pub fn removeEventListener(
        self: *Node,
        event_type: AtomId,
        callback: *const fn (ctx: *anyopaque, event: *anyopaque) void,
    ) void {
        var i: usize = 0;
        while (i < self.listeners.items.len) {
            const item = self.listeners.items[i];
            if (item.event_type == event_type and item.callback == callback) {
                _ = self.listeners.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn findFirst(self: *Node, id_atom: AtomId, id: []const u8) ?*Node {
        if (self.node_type == .Element) {
            if (self.getAttribute(id_atom)) |val| {
                if (std.mem.eql(u8, val, id)) return self;
            }
        }

        var curr = self.first_child;
        while (curr) |child| {
            if (child.findFirst(id_atom, id)) |found| return found;
            curr = child.next_sibling;
        }
        return null;
    }

    pub fn hasAttribute(self: *const Node, name: AtomId) bool {
        return self.getAttribute(name) != null;
    }

    // WHATWG classList (DOMTokenList)
    pub fn classList(self: *Node, table: *AtomTable) DOMTokenList {
        return .{ .node = self, .table = table };
    }

    // WHATWG dataset (data-* attributes)
    pub fn getDataset(self: *const Node, table: *AtomTable, key: []const u8) ?[]const u8 {
        var buf: [128]u8 = undefined;
        const attr_name = if (std.mem.startsWith(u8, key, "data-"))
            key
        else
            std.fmt.bufPrint(&buf, "data-{s}", .{key}) catch return null;
        const attr_atom = table.intern(attr_name) catch return null;
        return self.getAttribute(attr_atom);
    }

    pub fn setDataset(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, key: []const u8, val: []const u8) !void {
        var buf: [128]u8 = undefined;
        const attr_name = if (std.mem.startsWith(u8, key, "data-"))
            key
        else
            try std.fmt.bufPrint(&buf, "data-{s}", .{key});
        const attr_atom = try table.intern(attr_name);
        try self.setAttribute(allocator, attr_atom, val);
    }

    // WHATWG Element Traversal
    pub fn firstElementChild(self: *const Node) ?*Node {
        var curr = self.first_child;
        while (curr) |child| {
            if (child.node_type == .Element) return child;
            curr = child.next_sibling;
        }
        return null;
    }

    pub fn lastElementChild(self: *const Node) ?*Node {
        var curr = self.last_child;
        while (curr) |child| {
            if (child.node_type == .Element) return child;
            curr = child.prev_sibling;
        }
        return null;
    }

    pub fn nextElementSibling(self: *const Node) ?*Node {
        var curr = self.next_sibling;
        while (curr) |sib| {
            if (sib.node_type == .Element) return sib;
            curr = sib.next_sibling;
        }
        return null;
    }

    pub fn previousElementSibling(self: *const Node) ?*Node {
        var curr = self.prev_sibling;
        while (curr) |sib| {
            if (sib.node_type == .Element) return sib;
            curr = sib.prev_sibling;
        }
        return null;
    }

    pub fn childElementCount(self: *const Node) usize {
        var count: usize = 0;
        var curr = self.first_child;
        while (curr) |child| {
            if (child.node_type == .Element) count += 1;
            curr = child.next_sibling;
        }
        return count;
    }

    pub fn parentElement(self: *const Node) ?*Node {
        if (self.parent_node) |p| {
            if (p.node_type == .Element) return p;
        }
        return null;
    }

    const CombinatorInfo = struct {
        idx: usize,
        op: u8,
    };

    fn findLastCombinator(sel: []const u8) ?CombinatorInfo {
        var bracket_depth: usize = 0;
        var paren_depth: usize = 0;

        var i: usize = sel.len;
        while (i > 0) {
            i -= 1;
            const c = sel[i];
            if (c == ']') {
                bracket_depth += 1;
            } else if (c == '[') {
                if (bracket_depth > 0) bracket_depth -= 1;
            } else if (c == ')') {
                paren_depth += 1;
            } else if (c == '(') {
                if (paren_depth > 0) paren_depth -= 1;
            } else if (bracket_depth == 0 and paren_depth == 0) {
                if (c == '>') {
                    return CombinatorInfo{ .idx = i, .op = '>' };
                } else if (c == ' ') {
                    const before = std.mem.trimEnd(u8, sel[0..i], " \t");
                    const after = std.mem.trimStart(u8, sel[i + 1 ..], " \t");
                    if (before.len > 0 and after.len > 0 and before[before.len - 1] != '>' and after[0] != '>') {
                        return CombinatorInfo{ .idx = i, .op = ' ' };
                    }
                }
            }
        }
        return null;
    }

    pub fn evaluateNthExpression(index: i32, expr: []const u8) bool {
        const trimmed = std.mem.trim(u8, expr, " \t\r\n");
        if (trimmed.len == 0) return false;

        if (std.ascii.eqlIgnoreCase(trimmed, "odd")) {
            return @mod(index, 2) != 0;
        }
        if (std.ascii.eqlIgnoreCase(trimmed, "even")) {
            return @mod(index, 2) == 0;
        }

        if (std.mem.indexOfScalar(u8, trimmed, 'n') orelse std.mem.indexOfScalar(u8, trimmed, 'N')) |n_pos| {
            const a_str = std.mem.trim(u8, trimmed[0..n_pos], " \t+");
            const a: i32 = if (a_str.len == 0)
                1
            else if (std.mem.eql(u8, a_str, "-"))
                -1
            else
                std.fmt.parseInt(i32, a_str, 10) catch return false;

            const rest = std.mem.trim(u8, trimmed[n_pos + 1 ..], " \t");
            const b: i32 = if (rest.len == 0)
                0
            else blk: {
                const clean_b = if (std.mem.startsWith(u8, rest, "+"))
                    std.mem.trim(u8, rest[1..], " \t")
                else
                    rest;
                break :blk std.fmt.parseInt(i32, clean_b, 10) catch return false;
            };

            if (a == 0) return index == b;
            const diff = index - b;
            return (@mod(diff, a) == 0) and (@divFloor(diff, a) >= 0);
        } else {
            const k = std.fmt.parseInt(i32, trimmed, 10) catch return false;
            return index == k;
        }
    }

    // WHATWG matches and closest
    pub fn matches(self: *const Node, table: *AtomTable, selector_str: []const u8) bool {
        if (self.node_type != .Element) return false;
        const trimmed = std.mem.trim(u8, selector_str, " \t\r\n");
        if (trimmed.len == 0) return false;

        // 1. Check for top-level comma outside brackets and parens
        var bracket_depth: usize = 0;
        var paren_depth: usize = 0;
        var last_start: usize = 0;
        var has_top_level_comma = false;
        for (trimmed, 0..) |c, idx| {
            if (c == '[') {
                bracket_depth += 1;
            } else if (c == ']') {
                if (bracket_depth > 0) bracket_depth -= 1;
            } else if (c == '(') {
                paren_depth += 1;
            } else if (c == ')') {
                if (paren_depth > 0) paren_depth -= 1;
            } else if (c == ',' and bracket_depth == 0 and paren_depth == 0) {
                has_top_level_comma = true;
                const part = std.mem.trim(u8, trimmed[last_start..idx], " \t\r\n");
                if (part.len > 0 and self.matches(table, part)) return true;
                last_start = idx + 1;
            }
        }
        if (has_top_level_comma) {
            const part = std.mem.trim(u8, trimmed[last_start..], " \t\r\n");
            return part.len > 0 and self.matches(table, part);
        }

        // 2. Check for combinators (> and space)
        if (findLastCombinator(trimmed)) |comb| {
            const left = std.mem.trim(u8, trimmed[0..comb.idx], " \t\r\n");
            const right = std.mem.trim(u8, trimmed[comb.idx + 1 ..], " \t\r\n");
            if (left.len > 0 and right.len > 0) {
                if (!self.matchesCompound(table, right)) return false;
                if (comb.op == '>') {
                    if (self.parent_node) |p| {
                        return p.node_type == .Element and p.matches(table, left);
                    }
                    return false;
                } else if (comb.op == ' ') {
                    var p = self.parent_node;
                    while (p) |par| {
                        if (par.node_type == .Element and par.matches(table, left)) return true;
                        p = par.parent_node;
                    }
                    return false;
                }
            }
        }

        // 3. Single compound selector
        return self.matchesCompound(table, trimmed);
    }

    fn matchesCompound(self: *const Node, table: *AtomTable, trimmed: []const u8) bool {
        if (self.node_type != .Element) return false;
        if (trimmed.len == 0) return false;

        var i: usize = 0;
        // 1. Tag name (if any)
        if (trimmed[0] != '#' and trimmed[0] != '.' and trimmed[0] != '[' and trimmed[0] != ':') {
            const tag_end = std.mem.indexOfAny(u8, trimmed, "#.[:") orelse trimmed.len;
            const tag_part = trimmed[0..tag_end];
            if (!std.mem.eql(u8, tag_part, "*")) {
                const tag_name = table.get(self.tag_name);
                if (!std.ascii.eqlIgnoreCase(tag_name, tag_part)) return false;
            }
            i = tag_end;
        }

        // 2. Modifiers: #id, .class, [attr], :pseudo
        while (i < trimmed.len) {
            const ch = trimmed[i];
            if (ch == '#') {
                i += 1;
                const id_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
                const id_val = trimmed[i .. i + id_end];
                i += id_end;
                const id_atom = table.intern("id") catch return false;
                const actual_id = self.getAttribute(id_atom) orelse return false;
                if (!std.mem.eql(u8, actual_id, id_val)) return false;
            } else if (ch == '.') {
                i += 1;
                const class_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
                const class_val = trimmed[i .. i + class_end];
                i += class_end;
                const class_atom = table.intern("class") catch return false;
                const actual_class = self.getAttribute(class_atom) orelse return false;
                var found = false;
                var it = std.mem.tokenizeScalar(u8, actual_class, ' ');
                while (it.next()) |token| {
                    if (std.mem.eql(u8, token, class_val)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            } else if (ch == '[') {
                const close_bracket = std.mem.indexOfScalar(u8, trimmed[i..], ']') orelse return false;
                const attr_expr = trimmed[i + 1 .. i + close_bracket];
                i += close_bracket + 1;

                if (std.mem.indexOf(u8, attr_expr, "^=")) |p_idx| {
                    const attr_name = std.mem.trim(u8, attr_expr[0..p_idx], " \t'\"");
                    const attr_val = std.mem.trim(u8, attr_expr[p_idx + 2 ..], " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    const actual_val = self.getAttribute(attr_atom) orelse return false;
                    if (!std.mem.startsWith(u8, actual_val, attr_val)) return false;
                } else if (std.mem.indexOf(u8, attr_expr, "$=")) |s_idx| {
                    const attr_name = std.mem.trim(u8, attr_expr[0..s_idx], " \t'\"");
                    const attr_val = std.mem.trim(u8, attr_expr[s_idx + 2 ..], " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    const actual_val = self.getAttribute(attr_atom) orelse return false;
                    if (!std.mem.endsWith(u8, actual_val, attr_val)) return false;
                } else if (std.mem.indexOf(u8, attr_expr, "*=")) |c_idx| {
                    const attr_name = std.mem.trim(u8, attr_expr[0..c_idx], " \t'\"");
                    const attr_val = std.mem.trim(u8, attr_expr[c_idx + 2 ..], " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    const actual_val = self.getAttribute(attr_atom) orelse return false;
                    if (std.mem.indexOf(u8, actual_val, attr_val) == null) return false;
                } else if (std.mem.indexOf(u8, attr_expr, "~=")) |w_idx| {
                    const attr_name = std.mem.trim(u8, attr_expr[0..w_idx], " \t'\"");
                    const attr_val = std.mem.trim(u8, attr_expr[w_idx + 2 ..], " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    const actual_val = self.getAttribute(attr_atom) orelse return false;
                    var found = false;
                    var it = std.mem.tokenizeScalar(u8, actual_val, ' ');
                    while (it.next()) |token| {
                        if (std.mem.eql(u8, token, attr_val)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) return false;
                } else if (std.mem.indexOfScalar(u8, attr_expr, '=')) |eq_idx| {
                    const attr_name = std.mem.trim(u8, attr_expr[0..eq_idx], " \t'\"");
                    const attr_val = std.mem.trim(u8, attr_expr[eq_idx + 1 ..], " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    const actual_val = self.getAttribute(attr_atom) orelse return false;
                    if (!std.mem.eql(u8, actual_val, attr_val)) return false;
                } else {
                    const attr_name = std.mem.trim(u8, attr_expr, " \t'\"");
                    const attr_atom = table.intern(attr_name) catch return false;
                    if (!self.hasAttribute(attr_atom)) return false;
                }
            } else if (ch == ':') {
                i += 1;
                if (std.mem.startsWith(u8, trimmed[i..], "not(")) {
                    i += 4;
                    const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                    const inner_sel = trimmed[i .. i + close_p];
                    i += close_p + 1;
                    if (self.matches(table, inner_sel)) return false;
                } else if (std.mem.startsWith(u8, trimmed[i..], "nth-child(")) {
                    i += 10;
                    const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                    const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                    i += close_p + 1;
                    var idx: i32 = 1;
                    var p = self.prev_sibling;
                    while (p) |prev| {
                        if (prev.node_type == .Element) idx += 1;
                        p = prev.prev_sibling;
                    }
                    if (!evaluateNthExpression(idx, expr)) return false;
                } else if (std.mem.startsWith(u8, trimmed[i..], "nth-last-child(")) {
                    i += 15;
                    const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                    const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                    i += close_p + 1;
                    var idx: i32 = 1;
                    var n = self.next_sibling;
                    while (n) |next| {
                        if (next.node_type == .Element) idx += 1;
                        n = next.next_sibling;
                    }
                    if (!evaluateNthExpression(idx, expr)) return false;
                } else if (std.mem.startsWith(u8, trimmed[i..], "nth-of-type(")) {
                    i += 12;
                    const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                    const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                    i += close_p + 1;
                    var idx: i32 = 1;
                    var p = self.prev_sibling;
                    while (p) |prev| {
                        if (prev.node_type == .Element and prev.tag_name == self.tag_name) idx += 1;
                        p = prev.prev_sibling;
                    }
                    if (!evaluateNthExpression(idx, expr)) return false;
                } else if (std.mem.startsWith(u8, trimmed[i..], "nth-last-of-type(")) {
                    i += 17;
                    const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                    const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                    i += close_p + 1;
                    var idx: i32 = 1;
                    var n = self.next_sibling;
                    while (n) |next| {
                        if (next.node_type == .Element and next.tag_name == self.tag_name) idx += 1;
                        n = next.next_sibling;
                    }
                    if (!evaluateNthExpression(idx, expr)) return false;
                } else {
                    const pseudo_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
                    const pseudo = trimmed[i .. i + pseudo_end];
                    i += pseudo_end;

                    if (std.mem.eql(u8, pseudo, "first-child")) {
                        var p = self.prev_sibling;
                        while (p) |prev| {
                            if (prev.node_type == .Element) return false;
                            p = prev.prev_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "last-child")) {
                        var n = self.next_sibling;
                        while (n) |next| {
                            if (next.node_type == .Element) return false;
                            n = next.next_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "only-child")) {
                        var p = self.prev_sibling;
                        while (p) |prev| {
                            if (prev.node_type == .Element) return false;
                            p = prev.prev_sibling;
                        }
                        var n = self.next_sibling;
                        while (n) |next| {
                            if (next.node_type == .Element) return false;
                            n = next.next_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "first-of-type")) {
                        var p = self.prev_sibling;
                        while (p) |prev| {
                            if (prev.node_type == .Element and prev.tag_name == self.tag_name) return false;
                            p = prev.prev_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "last-of-type")) {
                        var n = self.next_sibling;
                        while (n) |next| {
                            if (next.node_type == .Element and next.tag_name == self.tag_name) return false;
                            n = next.next_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "only-of-type")) {
                        var p = self.prev_sibling;
                        while (p) |prev| {
                            if (prev.node_type == .Element and prev.tag_name == self.tag_name) return false;
                            p = prev.prev_sibling;
                        }
                        var n = self.next_sibling;
                        while (n) |next| {
                            if (next.node_type == .Element and next.tag_name == self.tag_name) return false;
                            n = next.next_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "empty")) {
                        var curr = self.first_child;
                        while (curr) |c| {
                            if (c.node_type == .Element) return false;
                            if (c.node_type == .Text) {
                                if (c.text_content) |tc| {
                                    if (std.mem.trim(u8, tc, " \t\r\n").len > 0) return false;
                                }
                            }
                            curr = c.next_sibling;
                        }
                    } else if (std.mem.eql(u8, pseudo, "checked")) {
                        const chk_atom = table.intern("checked") catch return false;
                        const sel_atom = table.intern("selected") catch return false;
                        if (!self.hasAttribute(chk_atom) and !self.hasAttribute(sel_atom)) return false;
                    } else if (std.mem.eql(u8, pseudo, "disabled")) {
                        const dis_atom = table.intern("disabled") catch return false;
                        if (!self.hasAttribute(dis_atom)) return false;
                    } else if (std.mem.eql(u8, pseudo, "enabled")) {
                        const dis_atom = table.intern("disabled") catch return false;
                        if (self.hasAttribute(dis_atom)) return false;
                    } else if (std.mem.eql(u8, pseudo, "root")) {
                        if (self.parent_node != null and !std.mem.eql(u8, table.get(self.tag_name), "html")) return false;
                    }
                }
            } else {
                break;
            }
        }
        return true;
    }

    pub fn closest(self: *Node, table: *AtomTable, selector_str: []const u8) ?*Node {
        var curr: ?*Node = self;
        while (curr) |n| {
            if (n.matches(table, selector_str)) return n;
            curr = n.parent_node;
        }
        return null;
    }

    // WHATWG textContent
    pub fn getTextContent(self: *const Node, allocator: std.mem.Allocator) anyerror![]u8 {
        if (self.node_type == .Text or self.node_type == .Comment) {
            return allocator.dupe(u8, self.text_content orelse "");
        }
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        try self.collectText(&list, allocator);
        return list.toOwnedSlice(allocator);
    }

    fn collectText(self: *const Node, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
        var curr = self.first_child;
        while (curr) |child| {
            if (child.node_type == .Text) {
                if (child.text_content) |tc| {
                    try out.appendSlice(allocator, tc);
                }
            } else if (child.node_type == .Element) {
                try child.collectText(out, allocator);
            }
            curr = child.next_sibling;
        }
    }

    pub fn setTextContent(self: *Node, allocator: std.mem.Allocator, text: []const u8) !void {
        if (self.node_type == .Text or self.node_type == .Comment) {
            if (self.text_content) |old| allocator.free(old);
            self.text_content = try allocator.dupe(u8, text);
            return;
        }

        var curr = self.first_child;
        while (curr) |child| {
            const next = child.next_sibling;
            child.deinit(allocator);
            curr = next;
        }
        self.first_child = null;
        self.last_child = null;

        if (text.len > 0) {
            const tn = try Node.createText(allocator, text);
            try self.appendChild(allocator, tn);
        }
    }

    // WHATWG innerHTML and outerHTML
    pub fn getInnerHTML(self: *const Node, allocator: std.mem.Allocator, table: *AtomTable) anyerror![]u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        var curr = self.first_child;
        while (curr) |child| {
            try child.serializeTo(allocator, table, &list);
            curr = child.next_sibling;
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn getOuterHTML(self: *const Node, allocator: std.mem.Allocator, table: *AtomTable) anyerror![]u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        try self.serializeTo(allocator, table, &list);
        return list.toOwnedSlice(allocator);
    }

    pub fn setInnerHTML(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, html: []const u8) !void {
        var curr = self.first_child;
        while (curr) |child| {
            const next = child.next_sibling;
            child.deinit(allocator);
            curr = next;
        }
        self.first_child = null;
        self.last_child = null;

        const TreeBuilder = @import("../html/tree_builder.zig").TreeBuilder;
        try TreeBuilder.parseFragment(allocator, table, self, html);
    }

    fn serializeTo(self: *const Node, allocator: std.mem.Allocator, table: *AtomTable, out: *std.ArrayList(u8)) anyerror!void {
        switch (self.node_type) {
            .Text => {
                try out.appendSlice(allocator, self.text_content orelse "");
            },
            .Comment => {
                try out.appendSlice(allocator, "<!--");
                try out.appendSlice(allocator, self.text_content orelse "");
                try out.appendSlice(allocator, "-->");
            },
            .Element => {
                const tag = table.get(self.tag_name);
                try out.append(allocator, '<');
                try out.appendSlice(allocator, tag);
                for (self.attributes.items) |attr| {
                    try out.append(allocator, ' ');
                    try out.appendSlice(allocator, table.get(attr.name));
                    try out.appendSlice(allocator, "=\"");
                    try out.appendSlice(allocator, attr.value);
                    try out.append(allocator, '\"');
                }

                const is_void = std.mem.eql(u8, tag, "img") or
                    std.mem.eql(u8, tag, "br") or
                    std.mem.eql(u8, tag, "hr") or
                    std.mem.eql(u8, tag, "input") or
                    std.mem.eql(u8, tag, "meta") or
                    std.mem.eql(u8, tag, "link");

                if (is_void) {
                    try out.append(allocator, '>');
                    return;
                }

                try out.append(allocator, '>');
                var curr = self.first_child;
                while (curr) |child| {
                    try child.serializeTo(allocator, table, out);
                    curr = child.next_sibling;
                }
                try out.appendSlice(allocator, "</");
                try out.appendSlice(allocator, tag);
                try out.append(allocator, '>');
            },
            else => {},
        }
    }

    pub fn removeAttribute(self: *Node, allocator: std.mem.Allocator, name: AtomId) bool {
        for (self.attributes.items, 0..) |attr, i| {
            if (attr.name == name) {
                allocator.free(attr.value);
                SubsystemMemoryTracker.global.recordFree(.DOM, attr.value.len);
                _ = self.attributes.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn getElementsByTagName(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, tag_name: []const u8) !std.ArrayList(*Node) {
        var results = std.ArrayList(*Node).empty;
        const tag_atom = try table.intern(tag_name);
        try self.collectByTagName(allocator, tag_atom, &results);
        return results;
    }

    fn collectByTagName(self: *Node, allocator: std.mem.Allocator, tag_atom: AtomId, results: *std.ArrayList(*Node)) !void {
        if (self.node_type == .Element and self.tag_name == tag_atom) {
            try results.append(allocator, self);
        }
        var curr = self.first_child;
        while (curr) |child| {
            try child.collectByTagName(allocator, tag_atom, results);
            curr = child.next_sibling;
        }
    }

    pub fn getElementsByClassName(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, class_name: []const u8) !std.ArrayList(*Node) {
        var results = std.ArrayList(*Node).empty;
        const class_atom = try table.intern("class");
        try self.collectByClassName(allocator, class_atom, class_name, &results);
        return results;
    }

    fn collectByClassName(self: *Node, allocator: std.mem.Allocator, class_atom: AtomId, target_class: []const u8, results: *std.ArrayList(*Node)) !void {
        if (self.node_type == .Element) {
            if (self.getAttribute(class_atom)) |val| {
                var it = std.mem.tokenizeScalar(u8, val, ' ');
                while (it.next()) |token| {
                    if (std.mem.eql(u8, token, target_class)) {
                        try results.append(allocator, self);
                        break;
                    }
                }
            }
        }
        var curr = self.first_child;
        while (curr) |child| {
            try child.collectByClassName(allocator, class_atom, target_class, results);
            curr = child.next_sibling;
        }
    }

    pub fn querySelector(self: *Node, table: *AtomTable, selector: []const u8) ?*Node {
        const trimmed = std.mem.trim(u8, selector, " \t\r\n");
        if (trimmed.len == 0) return null;

        var curr = self.first_child;
        while (curr) |child| {
            if (child.matches(table, trimmed)) return child;
            if (child.querySelector(table, trimmed)) |found| return found;
            curr = child.next_sibling;
        }
        return null;
    }

    pub fn querySelectorAll(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, selector: []const u8) !std.ArrayList(*Node) {
        var results = std.ArrayList(*Node).empty;
        const trimmed = std.mem.trim(u8, selector, " \t\r\n");
        if (trimmed.len > 0) {
            try self.collectBySelector(allocator, table, trimmed, &results);
        }
        return results;
    }

    fn collectBySelector(self: *Node, allocator: std.mem.Allocator, table: *AtomTable, selector: []const u8, results: *std.ArrayList(*Node)) !void {
        var curr = self.first_child;
        while (curr) |child| {
            if (child.matches(table, selector)) {
                try results.append(allocator, child);
            }
            try child.collectBySelector(allocator, table, selector, results);
            curr = child.next_sibling;
        }
    }

    pub fn cloneNode(self: *const Node, allocator: std.mem.Allocator, deep: bool) !*Node {
        const copy = if (self.node_type == .Text)
            try Node.createText(allocator, self.text_content orelse "")
        else
            try Node.create(allocator, self.node_type, self.tag_name);

        for (self.attributes.items) |attr| {
            try copy.setAttribute(allocator, attr.name, attr.value);
        }

        if (deep) {
            var curr = self.first_child;
            while (curr) |child| {
                const child_copy = try child.cloneNode(allocator, true);
                try copy.appendChild(allocator, child_copy);
                curr = child.next_sibling;
            }
        }

        return copy;
    }

    pub fn contains(self: *const Node, other: *const Node) bool {
        if (self == other) return true;
        var curr = self.first_child;
        while (curr) |child| {
            if (child.contains(other)) return true;
            curr = child.next_sibling;
        }
        return false;
    }
};

test "dom node creation and hierarchy" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const doc_atom = try table.intern("#document");
    const div_atom = try table.intern("div");
    const span_atom = try table.intern("span");

    const doc = try Node.create(allocator, .Document, doc_atom);
    defer doc.deinit(allocator);

    const div = try Node.create(allocator, .Element, div_atom);
    try doc.appendChild(allocator, div);

    const span = try Node.create(allocator, .Element, span_atom);
    try div.appendChild(allocator, span);

    const text = try Node.createText(allocator, "Hello Davoth");
    try span.appendChild(allocator, text);

    try std.testing.expectEqual(doc.first_child, div);
    try std.testing.expectEqual(div.first_child, span);
    try std.testing.expectEqual(span.first_child, text);
    try std.testing.expectEqualStrings("Hello Davoth", text.text_content.?);
}

test "dom node querySelector, getElementsByTagName, getElementsByClassName, and cloneNode" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const root = try Node.create(allocator, .Element, try table.intern("div"));
    defer root.deinit(allocator);

    const p1 = try Node.create(allocator, .Element, try table.intern("p"));
    try p1.setAttribute(allocator, try table.intern("id"), "main-para");
    try p1.setAttribute(allocator, try table.intern("class"), "text-lead highlight");
    try root.appendChild(allocator, p1);

    const p2 = try Node.create(allocator, .Element, try table.intern("p"));
    try p2.setAttribute(allocator, try table.intern("class"), "highlight secondary");
    try root.appendChild(allocator, p2);

    // Test querySelector
    const found_id = root.querySelector(table, "#main-para");
    try std.testing.expect(found_id == p1);

    const found_class = root.querySelector(table, ".text-lead");
    try std.testing.expect(found_class == p1);

    const found_tag = root.querySelector(table, "p");
    try std.testing.expect(found_tag == p1);

    // Test querySelectorAll
    var qa_list = try root.querySelectorAll(allocator, table, "p.highlight");
    defer qa_list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), qa_list.items.len);
    try std.testing.expectEqual(p1, qa_list.items[0]);
    try std.testing.expectEqual(p2, qa_list.items[1]);

    // Test getElementsByTagName
    var p_list = try root.getElementsByTagName(allocator, table, "p");
    defer p_list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), p_list.items.len);

    // Test getElementsByClassName
    var hl_list = try root.getElementsByClassName(allocator, table, "highlight");
    defer hl_list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), hl_list.items.len);

    // Test hasAttribute and removeAttribute
    const id_atom = try table.intern("id");
    try std.testing.expect(p1.hasAttribute(id_atom));
    _ = p1.removeAttribute(allocator, id_atom);
    try std.testing.expect(!p1.hasAttribute(id_atom));

    // Test cloneNode deep
    const clone = try root.cloneNode(allocator, true);
    defer clone.deinit(allocator);
    try std.testing.expect(clone.first_child != null);
    try std.testing.expect(clone.first_child.?.next_sibling != null);
}

test "node insertBefore and replaceChild" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const root = try Node.create(allocator, .Element, try table.intern("div"));
    defer root.deinit(allocator);

    const first = try Node.create(allocator, .Element, try table.intern("span"));
    const last = try Node.create(allocator, .Element, try table.intern("b"));

    try root.appendChild(allocator, first);
    try root.appendChild(allocator, last);

    // Insert 'middle' before 'last'
    const middle = try Node.create(allocator, .Element, try table.intern("i"));
    try root.insertBefore(allocator, middle, last);

    try std.testing.expectEqual(first, root.first_child.?);
    try std.testing.expectEqual(middle, root.first_child.?.next_sibling.?);
    try std.testing.expectEqual(last, root.last_child.?);

    // Replace 'middle' with 'replacement'
    const replacement = try Node.create(allocator, .Element, try table.intern("u"));
    try root.replaceChild(allocator, replacement, middle);
    middle.deinit(allocator); // deinit old detached child

    try std.testing.expectEqual(replacement, root.first_child.?.next_sibling.?);
    try std.testing.expectEqual(last, replacement.next_sibling.?);
}

test "node element traversal matches and closest" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    // DOM structure:
    // <div id="card" class="container widget">
    //   "Text whitespace"
    //   <section class="body">
    //     <button id="submit-btn" data-action="save">Submit</button>
    //   </section>
    // </div>
    const card = try Node.create(allocator, .Element, try table.intern("div"));
    defer card.deinit(allocator);
    try card.setAttribute(allocator, try table.intern("id"), "card");
    try card.setAttribute(allocator, try table.intern("class"), "container widget");

    const text_node = try Node.createText(allocator, "   \n   ");
    try card.appendChild(allocator, text_node);

    const section = try Node.create(allocator, .Element, try table.intern("section"));
    try section.setAttribute(allocator, try table.intern("class"), "body");
    try card.appendChild(allocator, section);

    const button = try Node.create(allocator, .Element, try table.intern("button"));
    try button.setAttribute(allocator, try table.intern("id"), "submit-btn");
    try button.setAttribute(allocator, try table.intern("data-action"), "save");
    try section.appendChild(allocator, button);

    // 1. Element Traversal
    try std.testing.expectEqual(section, card.firstElementChild().?);
    try std.testing.expectEqual(section, card.lastElementChild().?);
    try std.testing.expectEqual(@as(usize, 1), card.childElementCount());
    try std.testing.expect(section.nextElementSibling() == null);
    try std.testing.expectEqual(card, section.parentElement().?);

    // 2. matches
    try std.testing.expect(button.matches(table, "button"));
    try std.testing.expect(button.matches(table, "#submit-btn"));
    try std.testing.expect(button.matches(table, "[data-action]"));
    try std.testing.expect(button.matches(table, "[data-action=save]"));
    try std.testing.expect(button.matches(table, "button#submit-btn[data-action=save]"));
    try std.testing.expect(card.matches(table, "div.container.widget"));
    try std.testing.expect(card.matches(table, "div#card.container"));
    try std.testing.expect(!button.matches(table, ".missing"));
    try std.testing.expect(!button.matches(table, "div#submit-btn"));

    // 2b. Combinators, comma lists, advanced attributes, and pseudo-classes
    try std.testing.expect(button.matches(table, "span, button, a"));
    try std.testing.expect(button.matches(table, "section > button"));
    try std.testing.expect(button.matches(table, "div button"));
    try std.testing.expect(button.matches(table, "div > section > button"));
    try std.testing.expect(button.matches(table, "[data-action^=sa]"));
    try std.testing.expect(button.matches(table, "[data-action$=ve]"));
    try std.testing.expect(button.matches(table, "[data-action*=av]"));
    try std.testing.expect(button.matches(table, "button:first-child"));
    try std.testing.expect(button.matches(table, "button:last-child"));
    try std.testing.expect(button.matches(table, "button:only-child"));
    try std.testing.expect(button.matches(table, "button:not([disabled])"));
    try std.testing.expect(!button.matches(table, "button:not([data-action])"));
    try std.testing.expectEqual(button, card.querySelector(table, "section > button").?);

    // 3. closest
    const closest_btn = button.closest(table, "button");
    try std.testing.expectEqual(button, closest_btn.?);

    const closest_sec = button.closest(table, ".body");
    try std.testing.expectEqual(section, closest_sec.?);

    const closest_card = button.closest(table, "#card");
    try std.testing.expectEqual(card, closest_card.?);

    const closest_card_compound = button.closest(table, "div.container.widget");
    try std.testing.expectEqual(card, closest_card_compound.?);

    const closest_nonexistent = button.closest(table, "article");
    try std.testing.expect(closest_nonexistent == null);
}

test "node classlist and dataset" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const el = try Node.create(allocator, .Element, try table.intern("div"));
    defer el.deinit(allocator);

    var cl = el.classList(table);

    // 1. Initial state
    try std.testing.expectEqualStrings("", cl.value());
    try std.testing.expect(!cl.contains("active"));

    // 2. Add classes
    try cl.add(allocator, "btn");
    try cl.add(allocator, "primary");
    try std.testing.expect(cl.contains("btn"));
    try std.testing.expect(cl.contains("primary"));
    try std.testing.expectEqualStrings("btn primary", cl.value());

    // 3. Toggle
    const toggled_off = try cl.toggle(allocator, "primary");
    try std.testing.expect(!toggled_off);
    try std.testing.expect(!cl.contains("primary"));

    const toggled_on = try cl.toggle(allocator, "primary");
    try std.testing.expect(toggled_on);
    try std.testing.expect(cl.contains("primary"));

    // 4. Replace
    const replaced = try cl.replace(allocator, "primary", "danger");
    try std.testing.expect(replaced);
    try std.testing.expect(!cl.contains("primary"));
    try std.testing.expect(cl.contains("danger"));

    // 5. Remove
    try cl.remove(allocator, "danger");
    try std.testing.expect(!cl.contains("danger"));
    try std.testing.expect(cl.contains("btn"));

    // 6. Dataset
    try el.setDataset(allocator, table, "action", "submit");
    try el.setDataset(allocator, table, "data-user-id", "42");
    try std.testing.expectEqualStrings("submit", el.getDataset(table, "action").?);
    try std.testing.expectEqualStrings("submit", el.getDataset(table, "data-action").?);
    try std.testing.expectEqualStrings("42", el.getDataset(table, "user-id").?);
    try std.testing.expect(el.getDataset(table, "missing") == null);
}

test "node textcontent innerhtml and outerhtml" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const root = try Node.create(allocator, .Element, try table.intern("div"));
    defer root.deinit(allocator);
    try root.setAttribute(allocator, try table.intern("id"), "panel");

    // 1. setInnerHTML dynamic fragment parsing
    try root.setInnerHTML(allocator, table, "<p class=\"info\">Hello <strong>World</strong></p><button>Submit</button>");

    // Verify children structure
    try std.testing.expectEqual(@as(usize, 2), root.childElementCount());
    const p_elem = root.firstElementChild().?;
    try std.testing.expectEqualStrings("info", p_elem.getAttribute(try table.intern("class")).?);

    // 2. getTextContent recursive collection
    const text_all = try root.getTextContent(allocator);
    defer allocator.free(text_all);
    try std.testing.expectEqualStrings("Hello WorldSubmit", text_all);

    // 3. getInnerHTML and getOuterHTML serialization
    const inner_html = try root.getInnerHTML(allocator, table);
    defer allocator.free(inner_html);
    try std.testing.expectEqualStrings("<p class=\"info\">Hello <strong>World</strong></p><button>Submit</button>", inner_html);

    const outer_html = try root.getOuterHTML(allocator, table);
    defer allocator.free(outer_html);
    try std.testing.expectEqualStrings("<div id=\"panel\"><p class=\"info\">Hello <strong>World</strong></p><button>Submit</button></div>", outer_html);

    // 4. setTextContent replacing children
    try root.setTextContent(allocator, "Just Plain Text");
    try std.testing.expectEqual(@as(usize, 0), root.childElementCount());
    const updated_text = try root.getTextContent(allocator);
    defer allocator.free(updated_text);
    try std.testing.expectEqualStrings("Just Plain Text", updated_text);
}
