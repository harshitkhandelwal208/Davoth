//! browser.storage API (local and sync partitions).
const std = @import("std");

pub const StorageArea = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) StorageArea {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *StorageArea) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn get(self: *const StorageArea, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn set(self: *StorageArea, key: []const u8, value: []const u8) !void {
        if (self.data.getEntry(key)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = try self.allocator.dupe(u8, value);
            return;
        }

        const k = try self.allocator.dupe(u8, key);
        const v = try self.allocator.dupe(u8, value);
        try self.data.put(k, v);
    }

    pub fn remove(self: *StorageArea, key: []const u8) void {
        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }
};

pub const ExtensionStorage = struct {
    local: StorageArea,
    sync: StorageArea,

    pub fn init(allocator: std.mem.Allocator) ExtensionStorage {
        return .{
            .local = StorageArea.init(allocator),
            .sync = StorageArea.init(allocator),
        };
    }

    pub fn deinit(self: *ExtensionStorage) void {
        self.local.deinit();
        self.sync.deinit();
    }
};

test "extension storage local put and get" {
    const allocator = std.testing.allocator;
    var ext_storage = ExtensionStorage.init(allocator);
    defer ext_storage.deinit();

    try ext_storage.local.set("user_token", "sec123");
    try std.testing.expectEqualStrings("sec123", ext_storage.local.get("user_token").?);
}
