//! Fetch API Request and Response implementations.
const std = @import("std");
const HttpClient = @import("../net/http1.zig").HttpClient;
const Response = @import("../net/http1.zig").Response;

pub const FetchRequest = struct {
    url: []const u8,
    method: []const u8 = "GET",
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,

    pub fn deinit(self: *FetchRequest, allocator: std.mem.Allocator) void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }
};

pub const FetchResponse = struct {
    status: u16,
    ok: bool,
    status_text: []const u8,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FetchResponse) void {
        self.allocator.free(self.body);
    }

    pub fn text(self: *const FetchResponse) []const u8 {
        return self.body;
    }
};

pub fn fetch(allocator: std.mem.Allocator, client: *HttpClient, url: []const u8) !FetchResponse {
    var resp = try client.get(url);
    defer resp.deinit();

    const body_copy = try allocator.dupe(u8, resp.body);
    const ok = resp.status_code >= 200 and resp.status_code < 300;

    return FetchResponse{
        .status = resp.status_code,
        .ok = ok,
        .status_text = if (ok) "OK" else "Error",
        .body = body_copy,
        .allocator = allocator,
    };
}
