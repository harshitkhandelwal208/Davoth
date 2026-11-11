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
