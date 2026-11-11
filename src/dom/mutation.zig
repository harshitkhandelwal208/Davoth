//! DOM MutationObserver implementation.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const Node = @import("node.zig").Node;

pub const MutationType = enum {
    ChildList,
    Attributes,
    CharacterData,
};

pub const MutationRecord = struct {
    record_type: MutationType,
    target: *Node,
    attribute_name: ?AtomId = null,
    added_nodes: []*Node,
    removed_nodes: []*Node,
};

pub const MutationObserverCallback = *const fn (ctx: *anyopaque, records: []const MutationRecord) void;

pub const MutationObserverInit = struct {
    child_list: bool = false,
    attributes: bool = false,
    character_data: bool = false,
    subtree: bool = false,
};

pub const MutationObserver = struct {
    allocator: std.mem.Allocator,
    callback: MutationObserverCallback,
    ctx: *anyopaque,
    target: ?*Node = null,
    options: MutationObserverInit = .{},
    queued_records: std.ArrayList(MutationRecord),

    pub fn init(allocator: std.mem.Allocator, cb: MutationObserverCallback, ctx: *anyopaque) !*MutationObserver {
        const obs = try allocator.create(MutationObserver);
        obs.* = .{
            .allocator = allocator,
            .callback = cb,
            .ctx = ctx,
            .target = null,
            .options = .{},
            .queued_records = .empty,
        };
        return obs;
    }

    pub fn deinit(self: *MutationObserver) void {
        self.queued_records.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn observe(self: *MutationObserver, target: *Node, options: MutationObserverInit) void {
        self.target = target;
        self.options = options;
    }

    pub fn notifyChildList(self: *MutationObserver, target: *Node, added: []*Node, removed: []*Node) !void {
        if (!self.options.child_list) return;
        if (self.target != target and !self.options.subtree) return;

        try self.queued_records.append(self.allocator, .{
            .record_type = .ChildList,
            .target = target,
            .added_nodes = added,
            .removed_nodes = removed,
        });
    }

    pub fn deliver(self: *MutationObserver) void {
        if (self.queued_records.items.len > 0) {
            self.callback(self.ctx, self.queued_records.items);
            self.queued_records.clearRetainingCapacity();
        }
    }
};

test "mutation observer childList" {
    const allocator = std.testing.allocator;
    const NodeMod = @import("node.zig");
    const node = try NodeMod.Node.create(allocator, .Element, AtomId.empty);
    defer node.deinit(allocator);

    var records_received: usize = 0;
    const Handler = struct {
        fn onMutate(ctx: *anyopaque, records: []const MutationRecord) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += records.len;
        }
    };

    const obs = try MutationObserver.init(allocator, Handler.onMutate, &records_received);
    defer obs.deinit();

    obs.observe(node, .{ .child_list = true });
    var empty_slice: [0]*NodeMod.Node = .{};
    try obs.notifyChildList(node, &empty_slice, &empty_slice);
    obs.deliver();

    try std.testing.expectEqual(@as(usize, 1), records_received);
}
