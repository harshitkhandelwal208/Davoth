//! Browser permissions manager (Camera, Microphone, Geolocation, Notifications).
const std = @import("std");

pub const PermissionType = enum {
    Camera,
    Microphone,
    Geolocation,
    Notifications,
    Clipboard,
};

pub const PermissionState = enum {
    Prompt,
    Granted,
    Denied,
};

pub const PermissionManager = struct {
    allocator: std.mem.Allocator,
    permissions: std.StringHashMap(PermissionState),

    pub fn init(allocator: std.mem.Allocator) PermissionManager {
        return .{
            .allocator = allocator,
            .permissions = std.StringHashMap(PermissionState).init(allocator),
        };
    }

    pub fn deinit(self: *PermissionManager) void {
        var it = self.permissions.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.permissions.deinit();
    }

    pub fn query(self: *const PermissionManager, origin: []const u8, perm: PermissionType) PermissionState {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ origin, @tagName(perm) }) catch return .Prompt;
        return self.permissions.get(key) orelse .Prompt;
    }

    pub fn set(self: *PermissionManager, origin: []const u8, perm: PermissionType, state: PermissionState) !void {
        var key_buf: [256]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ origin, @tagName(perm) });
        if (self.permissions.getEntry(key)) |entry| {
            entry.value_ptr.* = state;
            return;
        }
        const key_copy = try self.allocator.dupe(u8, key);
        try self.permissions.put(key_copy, state);
    }
};

test "permissions prompt and grant" {
    const allocator = std.testing.allocator;
    var mgr = PermissionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(PermissionState.Prompt, mgr.query("https://davoth.org", .Camera));
    try mgr.set("https://davoth.org", .Camera, .Granted);
    try std.testing.expectEqual(PermissionState.Granted, mgr.query("https://davoth.org", .Camera));
}
