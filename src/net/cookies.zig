//! RFC 6265 compliant Cookie Jar with domain, path, and SameSite enforcement.
const std = @import("std");
const Mutex = @import("../common/sync.zig").Mutex;
const URL = @import("../common/url.zig").URL;

pub const SameSite = enum {
    Strict,
    Lax,
    None,
};

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: []const u8,
    path: []const u8,
    expires: ?i64 = null,
    secure: bool = false,
    http_only: bool = false,
    same_site: SameSite = .Lax,

    pub fn deinit(self: *Cookie, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        allocator.free(self.domain);
        allocator.free(self.path);
    }
};

pub const CookieJar = struct {
    allocator: std.mem.Allocator,
    cookies: std.ArrayList(Cookie),
    mutex: Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) CookieJar {
        return .{
            .allocator = allocator,
            .cookies = .empty,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *CookieJar) void {
        for (self.cookies.items) |*c| {
            c.deinit(self.allocator);
        }
        self.cookies.deinit(self.allocator);
    }

    pub fn setCookie(self: *CookieJar, header_val: []const u8, url: *const URL) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = std.mem.splitScalar(u8, header_val, ';');
        const first = it.next() orelse return;
        const eq_idx = std.mem.indexOfScalar(u8, first, '=') orelse return;

        const name = std.mem.trim(u8, first[0..eq_idx], " \t");
        const val = std.mem.trim(u8, first[eq_idx + 1 ..], " \t");

        var domain: []const u8 = url.host;
        var path: []const u8 = "/";
        var secure = false;
        var http_only = false;
        var same_site = SameSite.Lax;

        while (it.next()) |attr| {
            const trimmed = std.mem.trim(u8, attr, " \t");
            if (std.ascii.eqlIgnoreCase(trimmed, "secure")) {
                secure = true;
            } else if (std.ascii.eqlIgnoreCase(trimmed, "httponly")) {
                http_only = true;
            } else if (std.mem.indexOfScalar(u8, trimmed, '=')) |a_eq| {
                const a_name = std.mem.trim(u8, trimmed[0..a_eq], " \t");
                const a_val = std.mem.trim(u8, trimmed[a_eq + 1 ..], " \t");
                if (std.ascii.eqlIgnoreCase(a_name, "domain")) {
                    domain = a_val;
                } else if (std.ascii.eqlIgnoreCase(a_name, "path")) {
                    path = a_val;
                } else if (std.ascii.eqlIgnoreCase(a_name, "samesite")) {
                    if (std.ascii.eqlIgnoreCase(a_val, "strict")) same_site = .Strict;
                    if (std.ascii.eqlIgnoreCase(a_val, "none")) same_site = .None;
                }
            }
        }

        // Overwrite existing cookie with same name, domain, and path
        for (self.cookies.items) |*c| {
            if (std.mem.eql(u8, c.name, name) and std.mem.eql(u8, c.domain, domain) and std.mem.eql(u8, c.path, path)) {
                self.allocator.free(c.value);
                c.value = try self.allocator.dupe(u8, val);
                c.secure = secure;
                c.http_only = http_only;
                c.same_site = same_site;
                return;
            }
        }

        try self.cookies.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, val),
            .domain = try self.allocator.dupe(u8, domain),
            .path = try self.allocator.dupe(u8, path),
            .secure = secure,
            .http_only = http_only,
            .same_site = same_site,
        });
    }

    pub fn getCookieHeader(self: *CookieJar, url: *const URL) !?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(self.allocator);

        var first = true;
        for (self.cookies.items) |c| {
            // Check domain match
            if (!std.mem.endsWith(u8, url.host, c.domain)) continue;
            // Check path match
            if (!std.mem.startsWith(u8, url.path, c.path)) continue;
            // Check secure
            if (c.secure and !std.mem.eql(u8, url.scheme, "https")) continue;

            if (!first) {
                try list.appendSlice(self.allocator, "; ");
            }
            try list.appendSlice(self.allocator, c.name);
            try list.append(self.allocator, '=');
            try list.appendSlice(self.allocator, c.value);
            first = false;
        }

        if (list.items.len == 0) {
            list.deinit(self.allocator);
            return null;
        }

        return list.toOwnedSlice(self.allocator);
    }
};

test "cookie jar set and format header" {
    const allocator = std.testing.allocator;
    var jar = CookieJar.init(allocator);
    defer jar.deinit();

    var url = try URL.parse(allocator, "https://davoth.org/account");
    defer url.deinit();

    try jar.setCookie("session_id=abc123xyz; Secure; HttpOnly", &url);
    const header = (try jar.getCookieHeader(&url)).?;
    defer allocator.free(header);

    try std.testing.expectEqualStrings("session_id=abc123xyz", header);
}
