//! Web Storage (LocalStorage and SessionStorage) engine.
const std = @import("std");

pub const Storage = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),
    max_bytes: usize = 10 * 1024 * 1024, // 10MB quota
    current_bytes: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Storage {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
            .max_bytes = 10 * 1024 * 1024,
            .current_bytes = 0,
        };
    }

    pub fn deinit(self: *Storage) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn getItem(self: *const Storage, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn setItem(self: *Storage, key: []const u8, value: []const u8) !void {
        const added_bytes = key.len + value.len;
        if (self.current_bytes + added_bytes > self.max_bytes) {
            return error.QuotaExceeded;
        }

        if (self.data.getEntry(key)) |entry| {
            self.current_bytes -= entry.value_ptr.*.len;
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = try self.allocator.dupe(u8, value);
            self.current_bytes += value.len;
            return;
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const val_copy = try self.allocator.dupe(u8, value);
        try self.data.put(key_copy, val_copy);
        self.current_bytes += added_bytes;
    }

    pub fn removeItem(self: *Storage, key: []const u8) void {
        if (self.data.fetchRemove(key)) |kv| {
            self.current_bytes -= kv.key.len + kv.value.len;
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }

    pub fn clear(self: *Storage) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearRetainingCapacity();
        self.current_bytes = 0;
    }

    pub fn length(self: *const Storage) usize {
        return self.data.count();
    }
};

test "localstorage item operations" {
    const allocator = std.testing.allocator;
    var storage = Storage.init(allocator);
    defer storage.deinit();

    try storage.setItem("theme", "dark");
    try std.testing.expectEqualStrings("dark", storage.getItem("theme").?);
    try std.testing.expectEqual(@as(usize, 1), storage.length());

    storage.removeItem("theme");
    try std.testing.expect(storage.getItem("theme") == null);
}
