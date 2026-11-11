//! ECMAScript Promises and Microtask Queue implementation.
const std = @import("std");
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;

pub const PromiseState = enum {
    Pending,
    Fulfilled,
    Rejected,
};

pub const Reaction = struct {
    callback: *const fn (ctx: *anyopaque, val: JSValue) void,
    ctx: *anyopaque,
};

pub const JSPromise = struct {
    allocator: std.mem.Allocator,
    state: PromiseState = .Pending,
    result: JSValue = JSValue.undefined_val,
    fulfill_reactions: std.ArrayList(Reaction),
    reject_reactions: std.ArrayList(Reaction),

    pub fn init(allocator: std.mem.Allocator) !*JSPromise {
        const promise = try allocator.create(JSPromise);
        promise.* = .{
            .allocator = allocator,
            .state = .Pending,
            .result = JSValue.undefined_val,
            .fulfill_reactions = .empty,
            .reject_reactions = .empty,
        };
        return promise;
    }

    pub fn deinit(self: *JSPromise) void {
        self.fulfill_reactions.deinit(self.allocator);
        self.reject_reactions.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn fulfill(self: *JSPromise, value: JSValue) void {
        if (self.state != .Pending) return;
        self.state = .Fulfilled;
        self.result = value;

        for (self.fulfill_reactions.items) |rx| {
            rx.callback(rx.ctx, value);
        }
    }

    pub fn reject(self: *JSPromise, reason: JSValue) void {
        if (self.state != .Pending) return;
        self.state = .Rejected;
        self.result = reason;

        for (self.reject_reactions.items) |rx| {
            rx.callback(rx.ctx, reason);
        }
    }

    pub fn addFulfillReaction(self: *JSPromise, rx: Reaction) !void {
        if (self.state == .Fulfilled) {
            rx.callback(rx.ctx, self.result);
        } else if (self.state == .Pending) {
            try self.fulfill_reactions.append(self.allocator, rx);
        }
    }

    pub fn addRejectReaction(self: *JSPromise, rx: Reaction) !void {
        if (self.state == .Rejected) {
            rx.callback(rx.ctx, self.result);
        } else if (self.state == .Pending) {
            try self.reject_reactions.append(self.allocator, rx);
        }
    }
};

pub const Microtask = struct {
    run_fn: *const fn (ctx: *anyopaque) void,
    ctx: *anyopaque,
};

pub const MicrotaskQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Microtask),

    pub fn init(allocator: std.mem.Allocator) MicrotaskQueue {
        return .{
            .allocator = allocator,
            .queue = .empty,
        };
    }

    pub fn deinit(self: *MicrotaskQueue) void {
        self.queue.deinit(self.allocator);
    }

    pub fn enqueue(self: *MicrotaskQueue, task: Microtask) !void {
        try self.queue.append(self.allocator, task);
    }

    pub fn runAll(self: *MicrotaskQueue) void {
        while (self.queue.items.len > 0) {
            const task = self.queue.orderedRemove(0);
            task.run_fn(task.ctx);
        }
    }
};

test "promise lifecycle and reactions" {
    const allocator = std.testing.allocator;
    const p = try JSPromise.init(allocator);
    defer p.deinit();

    var received_val: f64 = 0.0;
    const Handler = struct {
        fn onFulfill(ctx: *anyopaque, val: JSValue) void {
            const out_ptr: *f64 = @ptrCast(@alignCast(ctx));
            out_ptr.* = val.toFloat64();
        }
    };

    try p.addFulfillReaction(.{
        .callback = Handler.onFulfill,
        .ctx = &received_val,
    });

    p.fulfill(JSValue.fromFloat64(99.5));
    try std.testing.expectEqual(PromiseState.Fulfilled, p.state);
    try std.testing.expectEqual(@as(f64, 99.5), received_val);
}
