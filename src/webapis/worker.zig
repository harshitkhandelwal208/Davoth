//! Web Worker threading and postMessage communication channel.
const std = @import("std");
const Mutex = @import("../common/sync.zig").Mutex;

pub const Worker = struct {
    allocator: std.mem.Allocator,
    script_url: []const u8,
    inbox: std.ArrayList([]const u8),
    outbox: std.ArrayList([]const u8),
    mutex: Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, script_url: []const u8) !*Worker {
        const w = try allocator.create(Worker);
        w.* = .{
            .allocator = allocator,
            .script_url = try allocator.dupe(u8, script_url),
            .inbox = .empty,
            .outbox = .empty,
            .mutex = .{},
        };
        return w;
    }

    pub fn deinit(self: *Worker) void {
        self.allocator.free(self.script_url);
        for (self.inbox.items) |msg| self.allocator.free(msg);
        for (self.outbox.items) |msg| self.allocator.free(msg);
        self.inbox.deinit(self.allocator);
        self.outbox.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn postMessage(self: *Worker, msg: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const copy = try self.allocator.dupe(u8, msg);
        try self.inbox.append(self.allocator, copy);
    }

    pub fn readMessage(self: *Worker) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.inbox.items.len > 0) {
            return self.inbox.orderedRemove(0);
        }
        return null;
    }
};

test "worker post and read message" {
    const allocator = std.testing.allocator;
    const worker = try Worker.init(allocator, "worker.js");
    defer worker.deinit();

    try worker.postMessage("compute_heavy_task");
    const msg = worker.readMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("compute_heavy_task", msg.?);
    allocator.free(msg.?);
}
