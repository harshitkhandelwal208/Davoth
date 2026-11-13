//! RFC 3986 compliant URL parser, serializer, and base URL resolution.
const std = @import("std");

pub const URL = struct {
    allocator: std.mem.Allocator,
    scheme: []const u8,
    username: []const u8 = "",
    password: []const u8 = "",
    host: []const u8,
    port: u16,
    path: []const u8,
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,

    pub fn deinit(self: *URL) void {
        self.allocator.free(self.scheme);
        if (self.username.len > 0) self.allocator.free(self.username);
        if (self.password.len > 0) self.allocator.free(self.password);
        self.allocator.free(self.host);
        self.allocator.free(self.path);
        if (self.query) |q| self.allocator.free(q);
        if (self.fragment) |f| self.allocator.free(f);
    }

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !URL {
        if (input.len == 0) return error.EmptyUrl;

        var remaining = input;
        var scheme: []const u8 = "";

        // Parse scheme: [a-zA-Z][a-zA-Z0-9+.-]*:
        if (std.mem.indexOfScalar(u8, remaining, ':')) |colon_idx| {
            const scheme_candidate = remaining[0..colon_idx];
            var is_valid_scheme = false;
            if (scheme_candidate.len > 0 and std.ascii.isAlphabetic(scheme_candidate[0])) {
                is_valid_scheme = true;
                for (scheme_candidate[1..]) |c| {
                    if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '.' and c != '-') {
                        is_valid_scheme = false;
                        break;
                    }
                }
            }
            if (is_valid_scheme) {
                scheme = try allocator.dupe(u8, scheme_candidate);
                remaining = remaining[colon_idx + 1 ..];
            }
        }

        if (scheme.len == 0) {
            scheme = try allocator.dupe(u8, "http");
        }

        // Scheme lowercase
        const scheme_mut = try allocator.dupe(u8, scheme);
        allocator.free(scheme);
        for (scheme_mut) |*c| c.* = std.ascii.toLower(c.*);
        scheme = scheme_mut;

        var host: []const u8 = "";
        var port: u16 = if (std.mem.eql(u8, scheme, "https")) 443 else 80;
        var username: []const u8 = "";
        var password: []const u8 = "";

        // Check for authority: //user:pass@host:port
        if (std.mem.startsWith(u8, remaining, "//")) {
            remaining = remaining[2..];
            const authority_end = std.mem.indexOfAny(u8, remaining, "/?#") orelse remaining.len;
            var authority = remaining[0..authority_end];
            remaining = remaining[authority_end..];

            // Check userinfo
            if (std.mem.indexOfScalar(u8, authority, '@')) |at_idx| {
                const userinfo = authority[0..at_idx];
                authority = authority[at_idx + 1 ..];
                if (std.mem.indexOfScalar(u8, userinfo, ':')) |u_colon| {
                    username = try allocator.dupe(u8, userinfo[0..u_colon]);
                    password = try allocator.dupe(u8, userinfo[u_colon + 1 ..]);
                } else {
                    username = try allocator.dupe(u8, userinfo);
                }
            }

            // Check port
            if (std.mem.lastIndexOfScalar(u8, authority, ':')) |p_colon| {
                const port_str = authority[p_colon + 1 ..];
                if (std.fmt.parseInt(u16, port_str, 10)) |p| {
                    port = p;
                    host = try allocator.dupe(u8, authority[0..p_colon]);
                } else |_| {
                    host = try allocator.dupe(u8, authority);
                }
            } else {
                host = try allocator.dupe(u8, authority);
            }
        }

        // Lowercase host
        if (host.len > 0) {
            const host_mut = try allocator.dupe(u8, host);
            allocator.free(host);
            for (host_mut) |*c| c.* = std.ascii.toLower(c.*);
            host = host_mut;
        }

        // Parse path, query, fragment
        var path_str: []const u8 = "/";
        var query_str: ?[]const u8 = null;
        var fragment_str: ?[]const u8 = null;

        if (remaining.len > 0) {
            const frag_idx = std.mem.indexOfScalar(u8, remaining, '#');
            if (frag_idx) |idx| {
                fragment_str = try allocator.dupe(u8, remaining[idx + 1 ..]);
                remaining = remaining[0..idx];
            }

            const q_idx = std.mem.indexOfScalar(u8, remaining, '?');
            if (q_idx) |idx| {
                query_str = try allocator.dupe(u8, remaining[idx + 1 ..]);
                remaining = remaining[0..idx];
            }

            if (remaining.len > 0) {
                path_str = remaining;
            }
        }

        const path = try allocator.dupe(u8, path_str);

        return URL{
            .allocator = allocator,
            .scheme = scheme,
            .username = username,
            .password = password,
            .host = host,
            .port = port,
            .path = path,
            .query = query_str,
            .fragment = fragment_str,
        };
    }

    pub fn serialize(self: URL, allocator: std.mem.Allocator) ![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        try list.appendSlice(allocator, self.scheme);
        try list.appendSlice(allocator, "://");

        if (self.username.len > 0) {
            try list.appendSlice(allocator, self.username);
            if (self.password.len > 0) {
                try list.append(allocator, ':');
                try list.appendSlice(allocator, self.password);
            }
            try list.append(allocator, '@');
        }

        try list.appendSlice(allocator, self.host);

        const default_port: u16 = if (std.mem.eql(u8, self.scheme, "https")) 443 else 80;
        if (self.port != default_port and self.port != 0) {
            try list.append(allocator, ':');
            var buf: [16]u8 = undefined;
            const p_str = std.fmt.bufPrint(&buf, "{d}", .{self.port}) catch "80";
            try list.appendSlice(allocator, p_str);
        }

        if (self.path.len == 0 or self.path[0] != '/') {
            try list.append(allocator, '/');
        }
        try list.appendSlice(allocator, self.path);

        if (self.query) |q| {
            try list.append(allocator, '?');
            try list.appendSlice(allocator, q);
        }

        if (self.fragment) |f| {
            try list.append(allocator, '#');
            try list.appendSlice(allocator, f);
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn origin(self: URL, allocator: std.mem.Allocator) ![]u8 {
        const default_port: u16 = if (std.mem.eql(u8, self.scheme, "https")) 443 else 80;
        if (self.port == default_port or self.port == 0) {
            return std.fmt.allocPrint(allocator, "{s}://{s}", .{ self.scheme, self.host });
        } else {
            return std.fmt.allocPrint(allocator, "{s}://{s}:{d}", .{ self.scheme, self.host, self.port });
        }
    }

    pub fn resolve(self: URL, allocator: std.mem.Allocator, relative: []const u8) !URL {
        if (std.mem.indexOfScalar(u8, relative, ':')) |_| {
            // Absolute URL with scheme
            return URL.parse(allocator, relative);
        }

        if (std.mem.startsWith(u8, relative, "//")) {
            // Protocol relative
            const full = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ self.scheme, relative });
            defer allocator.free(full);
            return URL.parse(allocator, full);
        }

        if (std.mem.startsWith(u8, relative, "/")) {
            // Root relative path
            const base_origin = try self.origin(allocator);
            defer allocator.free(base_origin);
            const full = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_origin, relative });
            defer allocator.free(full);
            return URL.parse(allocator, full);
        }

        // Relative to current path folder
        var folder = self.path;
        if (std.mem.lastIndexOfScalar(u8, folder, '/')) |last_slash| {
            folder = folder[0 .. last_slash + 1];
        } else {
            folder = "/";
        }

        const base_origin = try self.origin(allocator);
        defer allocator.free(base_origin);
        const full = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base_origin, folder, relative });
        defer allocator.free(full);
        return URL.parse(allocator, full);
    }
};

pub const URLSearchParams = struct {
    pub const Param = struct {
        key: []const u8,
        value: []const u8,
    };

    allocator: std.mem.Allocator,
    params: std.ArrayList(Param),

    pub fn init(allocator: std.mem.Allocator, query_string: []const u8) !URLSearchParams {
        var list = std.ArrayList(Param).empty;
        errdefer {
            for (list.items) |p| {
                allocator.free(p.key);
                allocator.free(p.value);
            }
            list.deinit(allocator);
        }

        var raw = query_string;
        if (raw.len > 0 and raw[0] == '?') {
            raw = raw[1..];
        }

        var it = std.mem.splitScalar(u8, raw, '&');
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                const k = try allocator.dupe(u8, pair[0..eq]);
                errdefer allocator.free(k);
                const v = try allocator.dupe(u8, pair[eq + 1 ..]);
                try list.append(allocator, .{ .key = k, .value = v });
            } else {
                const k = try allocator.dupe(u8, pair);
                const v = try allocator.dupe(u8, "");
                try list.append(allocator, .{ .key = k, .value = v });
            }
        }

        return .{
            .allocator = allocator,
            .params = list,
        };
    }

    pub fn deinit(self: *URLSearchParams) void {
        for (self.params.items) |p| {
            self.allocator.free(p.key);
            self.allocator.free(p.value);
        }
        self.params.deinit(self.allocator);
    }

    pub fn get(self: *const URLSearchParams, name: []const u8) ?[]const u8 {
        for (self.params.items) |p| {
            if (std.mem.eql(u8, p.key, name)) return p.value;
        }
        return null;
    }

    pub fn has(self: *const URLSearchParams, name: []const u8) bool {
        return self.get(name) != null;
    }

    pub fn set(self: *URLSearchParams, name: []const u8, value: []const u8) !void {
        var found = false;
        var i: usize = 0;
        while (i < self.params.items.len) {
            if (std.mem.eql(u8, self.params.items[i].key, name)) {
                if (!found) {
                    self.allocator.free(self.params.items[i].value);
                    self.params.items[i].value = try self.allocator.dupe(u8, value);
                    found = true;
                    i += 1;
                } else {
                    const p = self.params.orderedRemove(i);
                    self.allocator.free(p.key);
                    self.allocator.free(p.value);
                }
            } else {
                i += 1;
            }
        }
        if (!found) {
            try self.append(name, value);
        }
    }

    pub fn append(self: *URLSearchParams, name: []const u8, value: []const u8) !void {
        const k = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(k);
        const v = try self.allocator.dupe(u8, value);
        try self.params.append(self.allocator, .{ .key = k, .value = v });
    }

    pub fn delete(self: *URLSearchParams, name: []const u8) void {
        var i: usize = 0;
        while (i < self.params.items.len) {
            if (std.mem.eql(u8, self.params.items[i].key, name)) {
                const p = self.params.orderedRemove(i);
                self.allocator.free(p.key);
                self.allocator.free(p.value);
            } else {
                i += 1;
            }
        }
    }

    pub fn toString(self: *const URLSearchParams, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        for (self.params.items, 0..) |p, idx| {
            if (idx > 0) try list.append(allocator, '&');
            try list.appendSlice(allocator, p.key);
            try list.append(allocator, '=');
            try list.appendSlice(allocator, p.value);
        }
        return list.toOwnedSlice(allocator);
    }
};

test "url parsing and origin" {
    const allocator = std.testing.allocator;
    var url = try URL.parse(allocator, "https://davoth.org:8443/docs/index.html?v=1#sec2");
    defer url.deinit();

    try std.testing.expectEqualStrings("https", url.scheme);
    try std.testing.expectEqualStrings("davoth.org", url.host);
    try std.testing.expectEqual(@as(u16, 8443), url.port);
    try std.testing.expectEqualStrings("/docs/index.html", url.path);
    try std.testing.expectEqualStrings("v=1", url.query.?);
    try std.testing.expectEqualStrings("sec2", url.fragment.?);

    const orig = try url.origin(allocator);
    defer allocator.free(orig);
    try std.testing.expectEqualStrings("https://davoth.org:8443", orig);

    // Resolve relative
    var resolved = try url.resolve(allocator, "style.css");
    defer resolved.deinit();
    try std.testing.expectEqualStrings("/docs/style.css", resolved.path);
}

test "urlsearchparams query string manipulation" {
    const allocator = std.testing.allocator;
    var usp = try URLSearchParams.init(allocator, "?tab=settings&theme=dark&count=5");
    defer usp.deinit();

    try std.testing.expect(usp.has("tab"));
    try std.testing.expectEqualStrings("settings", usp.get("tab").?);
    try std.testing.expectEqualStrings("dark", usp.get("theme").?);
    try std.testing.expectEqualStrings("5", usp.get("count").?);
    try std.testing.expect(!usp.has("nonexistent"));

    // Modify parameter
    try usp.set("theme", "sepia");
    try std.testing.expectEqualStrings("sepia", usp.get("theme").?);

    // Delete parameter
    usp.delete("count");
    try std.testing.expect(!usp.has("count"));

    // Append new parameter
    try usp.append("mode", "strict");
    try std.testing.expectEqualStrings("strict", usp.get("mode").?);

    // Serialize back to query string
    const qs = try usp.toString(allocator);
    defer allocator.free(qs);
    try std.testing.expectEqualStrings("tab=settings&theme=sepia&mode=strict", qs);
}
