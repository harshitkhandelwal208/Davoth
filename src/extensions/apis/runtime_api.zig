//! browser.runtime API messaging and resource URLs.
const std = @import("std");

pub const RuntimeMessageCallback = *const fn (ctx: *anyopaque, message: []const u8) ?[]const u8;

pub const RuntimeListener = struct {
    callback: RuntimeMessageCallback,
    ctx: *anyopaque,
};

pub const RuntimeApi = struct {
    allocator: std.mem.Allocator,
    extension_id: []const u8,
    listeners: std.ArrayList(RuntimeListener),

    pub fn init(allocator: std.mem.Allocator, extension_id: []const u8) !RuntimeApi {
        return .{
            .allocator = allocator,
            .extension_id = try allocator.dupe(u8, extension_id),
            .listeners = .empty,
        };
    }

    pub fn deinit(self: *RuntimeApi) void {
        self.allocator.free(self.extension_id);
        self.listeners.deinit(self.allocator);
    }

    pub fn addListener(self: *RuntimeApi, listener: RuntimeListener) !void {
        try self.listeners.append(self.allocator, listener);
    }

    pub fn sendMessage(self: *const RuntimeApi, message: []const u8) ?[]const u8 {
        for (self.listeners.items) |l| {
            if (l.callback(l.ctx, message)) |reply| {
                return reply;
            }
        }
        return null;
    }

    pub fn getURL(self: *const RuntimeApi, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "moz-extension://{s}/{s}", .{ self.extension_id, path });
    }
};

test "runtime api getURL and sendMessage" {
    const allocator = std.testing.allocator;
    var runtime = try RuntimeApi.init(allocator, "adnauseam@rednoise.org");
    defer runtime.deinit();

    const url = try runtime.getURL(allocator, "menu.html");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("moz-extension://adnauseam@rednoise.org/menu.html", url);
}
