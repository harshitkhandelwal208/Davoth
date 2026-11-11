//! Web Components: Shadow DOM, Custom Elements registry, and Template cloning.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const Node = @import("node.zig").Node;

pub const ShadowRootMode = enum {
    Open,
    Closed,
};

pub const ShadowRoot = struct {
    mode: ShadowRootMode,
    host: *Node,
    root_node: *Node,

    pub fn attach(allocator: std.mem.Allocator, host: *Node, mode: ShadowRootMode) !*ShadowRoot {
        const root = try Node.create(allocator, .DocumentFragment, AtomId.empty);
        const sr = try allocator.create(ShadowRoot);
        sr.* = .{
            .mode = mode,
            .host = host,
            .root_node = root,
        };
        host.shadow_root = root;
        return sr;
    }

    pub fn deinit(self: *ShadowRoot, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub const CustomElementCallbacks = struct {
    connected: ?*const fn (node: *Node) void = null,
    disconnected: ?*const fn (node: *Node) void = null,
    attribute_changed: ?*const fn (node: *Node, attr: AtomId, old_val: ?[]const u8, new_val: []const u8) void = null,
};

pub const CustomElementRegistry = struct {
    allocator: std.mem.Allocator,
    definitions: std.AutoHashMap(AtomId, CustomElementCallbacks),

    pub fn init(allocator: std.mem.Allocator) CustomElementRegistry {
        return .{
            .allocator = allocator,
            .definitions = std.AutoHashMap(AtomId, CustomElementCallbacks).init(allocator),
        };
    }

    pub fn deinit(self: *CustomElementRegistry) void {
        self.definitions.deinit();
    }

    pub fn define(self: *CustomElementRegistry, tag_name: AtomId, callbacks: CustomElementCallbacks) !void {
        try self.definitions.put(tag_name, callbacks);
    }

    pub fn get(self: *const CustomElementRegistry, tag_name: AtomId) ?CustomElementCallbacks {
        return self.definitions.get(tag_name);
    }
};

pub fn cloneNode(allocator: std.mem.Allocator, node: *const Node, deep: bool) !*Node {
    const copy = try Node.create(allocator, node.node_type, node.tag_name);
    if (node.text_content) |txt| {
        copy.text_content = try allocator.dupe(u8, txt);
    }

    for (node.attributes.items) |attr| {
        try copy.setAttribute(allocator, attr.name, attr.value);
    }

    if (deep) {
        var curr = node.first_child;
        while (curr) |child| {
            const child_copy = try cloneNode(allocator, child, true);
            try copy.appendChild(allocator, child_copy);
            curr = child.next_sibling;
        }
    }

    return copy;
}

test "web components shadow dom and clone" {
    const allocator = std.testing.allocator;
    const AtomTable = @import("../common/string.zig").AtomTable;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const host_atom = try table.intern("custom-card");
    const host = try Node.create(allocator, .Element, host_atom);
    defer host.deinit(allocator);

    const sr = try ShadowRoot.attach(allocator, host, .Open);
    defer sr.deinit(allocator);

    try std.testing.expect(host.shadow_root != null);

    const cloned = try cloneNode(allocator, host, false);
    defer cloned.deinit(allocator);
    try std.testing.expectEqual(host.tag_name, cloned.tag_name);
}
