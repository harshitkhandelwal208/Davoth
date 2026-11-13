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
        const trimmed = std.mem.trim(u8, selector, " ");
        if (trimmed.len == 0) return null;

        if (trimmed[0] == '#') {
            return self.getElementById(table, trimmed[1..]);
        }

        if (trimmed[0] == '.') {
            const class_atom = table.intern("class") catch return null;
            return self.findFirstClass(class_atom, trimmed[1..]);
        }

        const tag_atom = table.intern(trimmed) catch return null;
        return self.findFirstTag(tag_atom);
    }

    fn findFirstTag(self: *Node, tag_atom: AtomId) ?*Node {
        if (self.node_type == .Element and self.tag_name == tag_atom) return self;
        var curr = self.first_child;
        while (curr) |child| {
            if (child.findFirstTag(tag_atom)) |f| return f;
            curr = child.next_sibling;
        }
        return null;
    }

    fn findFirstClass(self: *Node, class_atom: AtomId, target_class: []const u8) ?*Node {
        if (self.node_type == .Element) {
            if (self.getAttribute(class_atom)) |val| {
                var it = std.mem.tokenizeScalar(u8, val, ' ');
                while (it.next()) |token| {
                    if (std.mem.eql(u8, token, target_class)) return self;
                }
            }
        }
        var curr = self.first_child;
        while (curr) |child| {
            if (child.findFirstClass(class_atom, target_class)) |f| return f;
            curr = child.next_sibling;
        }
        return null;
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
