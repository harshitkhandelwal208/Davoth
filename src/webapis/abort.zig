//! WHATWG AbortController and AbortSignal implementations.
const std = @import("std");

pub const AbortListener = struct {
    callback: *const fn (ctx: *anyopaque) void,
    ctx: *anyopaque,
};

pub const AbortSignal = struct {
    allocator: std.mem.Allocator,
    aborted: bool = false,
    reason: ?[]const u8 = null,
    listeners: std.ArrayList(AbortListener),

    pub fn init(allocator: std.mem.Allocator) !*AbortSignal {
        const sig = try allocator.create(AbortSignal);
        sig.* = .{
            .allocator = allocator,
            .aborted = false,
            .reason = null,
            .listeners = .empty,
        };
        return sig;
    }

    pub fn deinit(self: *AbortSignal) void {
        if (self.reason) |r| self.allocator.free(r);
        self.listeners.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn abort(self: *AbortSignal, reason: ?[]const u8) !void {
        if (self.aborted) return;
        self.aborted = true;
        if (reason) |r| {
            self.reason = try self.allocator.dupe(u8, r);
        } else {
            self.reason = try self.allocator.dupe(u8, "AbortError");
        }

        for (self.listeners.items) |lis| {
            lis.callback(lis.ctx);
        }
    }

    pub fn addEventListener(self: *AbortSignal, callback: *const fn (ctx: *anyopaque) void, ctx: *anyopaque) !void {
        if (self.aborted) {
            callback(ctx);
            return;
        }
        try self.listeners.append(self.allocator, .{ .callback = callback, .ctx = ctx });
    }
};

pub const AbortController = struct {
    allocator: std.mem.Allocator,
    signal: *AbortSignal,

    pub fn init(allocator: std.mem.Allocator) !*AbortController {
        const ctrl = try allocator.create(AbortController);
        const sig = try AbortSignal.init(allocator);
        ctrl.* = .{
            .allocator = allocator,
            .signal = sig,
        };
        return ctrl;
    }

    pub fn deinit(self: *AbortController) void {
        self.signal.deinit();
        self.allocator.destroy(self);
    }

    pub fn abort(self: *AbortController, reason: ?[]const u8) !void {
        try self.signal.abort(reason);
    }
};

test "abortcontroller and abortsignal lifecycle" {
    const allocator = std.testing.allocator;
    const controller = try AbortController.init(allocator);
    defer controller.deinit();

    try std.testing.expect(!controller.signal.aborted);
    try std.testing.expect(controller.signal.reason == null);

    const CallbackHelper = struct {
        fired: bool = false,
        fn onAbort(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.fired = true;
        }
    };
    var helper = CallbackHelper{};

    try controller.signal.addEventListener(CallbackHelper.onAbort, @ptrCast(&helper));
    try std.testing.expect(!helper.fired);

    try controller.abort("Request cancelled by client");
    try std.testing.expect(controller.signal.aborted);
    try std.testing.expectEqualStrings("Request cancelled by client", controller.signal.reason.?);
    try std.testing.expect(helper.fired);
}
