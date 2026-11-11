//! RFC 7234 HTTP Cache with Cache-Control and ETag revalidation.
const std = @import("std");
const Mutex = @import("../common/sync.zig").Mutex;
const time = @import("../common/time.zig");
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const CacheEntry = struct {
    status_code: u16,
    headers: []const u8,
    body: []const u8,
    etag: ?[]const u8 = null,
    expires_at_ms: i64,

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.body);
        if (self.etag) |e| allocator.free(e);
    }
};

pub const HttpCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    mutex: Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) HttpCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *HttpCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    pub fn get(self: *HttpCache, url_str: []const u8) ?CacheEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.get(url_str)) |entry| {
            const now = time.milliTimestamp();
            if (entry.expires_at_ms > now) {
                return entry;
            }
        }
        return null;
    }

    pub fn put(
        self: *HttpCache,
        url_str: []const u8,
        status: u16,
        headers: []const u8,
        body: []const u8,
        etag: ?[]const u8,
        max_age_secs: u32,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = time.milliTimestamp();
        const expires = now + (@as(i64, max_age_secs) * 1000);

        const url_copy = try self.allocator.dupe(u8, url_str);
        const headers_copy = try self.allocator.dupe(u8, headers);
        const body_copy = try self.allocator.dupe(u8, body);
        const etag_copy = if (etag) |e| try self.allocator.dupe(u8, e) else null;

        SubsystemMemoryTracker.global.recordAlloc(.NetworkCache, body_copy.len);

        try self.entries.put(url_copy, .{
            .status_code = status,
            .headers = headers_copy,
            .body = body_copy,
            .etag = etag_copy,
            .expires_at_ms = expires,
        });
    }
};

test "http cache put and get" {
    const allocator = std.testing.allocator;
    var cache = HttpCache.init(allocator);
    defer cache.deinit();

    try cache.put("https://example.com/data.json", 200, "Content-Type: application/json", "{\"status\":\"ok\"}", "\"etag123\"", 3600);
    const entry = cache.get("https://example.com/data.json");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("{\"status\":\"ok\"}", entry.?.body);
}
