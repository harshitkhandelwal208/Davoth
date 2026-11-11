//! IndexedDB client-side transactional object store.
const std = @import("std");

pub const IDBObjectStore = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    records: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*IDBObjectStore {
        const store = try allocator.create(IDBObjectStore);
        store.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .records = std.StringHashMap([]const u8).init(allocator),
        };
        return store;
    }

    pub fn deinit(self: *IDBObjectStore) void {
        self.allocator.free(self.name);
        var it = self.records.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.records.deinit();
        self.allocator.destroy(self);
    }

    pub fn put(self: *IDBObjectStore, key: []const u8, value: []const u8) !void {
        if (self.records.getEntry(key)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = try self.allocator.dupe(u8, value);
            return;
        }

        const k = try self.allocator.dupe(u8, key);
        const v = try self.allocator.dupe(u8, value);
        try self.records.put(k, v);
    }

    pub fn get(self: *const IDBObjectStore, key: []const u8) ?[]const u8 {
        return self.records.get(key);
    }

    pub fn delete(self: *IDBObjectStore, key: []const u8) void {
        if (self.records.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }
};

pub const IDBDatabase = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: u32,
    stores: std.StringHashMap(*IDBObjectStore),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: u32) !*IDBDatabase {
        const db = try allocator.create(IDBDatabase);
        db.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .version = version,
            .stores = std.StringHashMap(*IDBObjectStore).init(allocator),
        };
        return db;
    }

    pub fn deinit(self: *IDBDatabase) void {
        self.allocator.free(self.name);
        var it = self.stores.valueIterator();
        while (it.next()) |store| {
            store.*.deinit();
        }
        self.stores.deinit();
        self.allocator.destroy(self);
    }

    pub fn createObjectStore(self: *IDBDatabase, name: []const u8) !*IDBObjectStore {
        const store = try IDBObjectStore.init(self.allocator, name);
        try self.stores.put(store.name, store);
        return store;
    }
};

test "indexeddb put and get" {
    const allocator = std.testing.allocator;
    const db = try IDBDatabase.init(allocator, "davoth_app_db", 1);
    defer db.deinit();

    const store = try db.createObjectStore("settings");
    try store.put("sync_enabled", "true");
    try std.testing.expectEqualStrings("true", store.get("sync_enabled").?);
}
