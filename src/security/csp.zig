//! Content Security Policy (CSP) parsing and directive enforcement.
const std = @import("std");

pub const CSPDirective = struct {
    name: []const u8,
    sources: std.ArrayList([]const u8),

    pub fn deinit(self: *CSPDirective, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.sources.items) |s| allocator.free(s);
        self.sources.deinit(allocator);
    }

    pub fn allows(self: *const CSPDirective, source: []const u8) bool {
        for (self.sources.items) |s| {
            if (std.mem.eql(u8, s, "*")) return true;
            if (std.mem.eql(u8, s, "'self'")) {
                if (std.mem.startsWith(u8, source, "self") or std.mem.startsWith(u8, source, "/")) return true;
            }
            if (std.mem.eql(u8, s, source)) return true;
        }
        return false;
    }
};

pub const ContentSecurityPolicy = struct {
    allocator: std.mem.Allocator,
    directives: std.ArrayList(CSPDirective),

    pub fn parse(allocator: std.mem.Allocator, header_val: []const u8) !ContentSecurityPolicy {
        var dirs: std.ArrayList(CSPDirective) = .empty;
        errdefer dirs.deinit(allocator);

        var it = std.mem.splitScalar(u8, header_val, ';');
        while (it.next()) |dir_str| {
            const trimmed = std.mem.trim(u8, dir_str, " \t\r\n");
            if (trimmed.len == 0) continue;

            var tokens = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const dir_name = tokens.next() orelse continue;

            var sources: std.ArrayList([]const u8) = .empty;
            errdefer sources.deinit(allocator);

            while (tokens.next()) |src| {
                try sources.append(allocator, try allocator.dupe(u8, src));
            }

            try dirs.append(allocator, .{
                .name = try allocator.dupe(u8, dir_name),
                .sources = sources,
            });
        }

        return .{
            .allocator = allocator,
            .directives = dirs,
        };
    }

    pub fn deinit(self: *ContentSecurityPolicy) void {
        for (self.directives.items) |*d| {
            d.deinit(self.allocator);
        }
        self.directives.deinit(self.allocator);
    }

    pub fn allowsScript(self: *const ContentSecurityPolicy, src: []const u8) bool {
        return self.allowsDirective("script-src", src);
    }

    pub fn allowsConnect(self: *const ContentSecurityPolicy, src: []const u8) bool {
        return self.allowsDirective("connect-src", src);
    }

    fn allowsDirective(self: *const ContentSecurityPolicy, dir_name: []const u8, src: []const u8) bool {
        for (self.directives.items) |d| {
            if (std.ascii.eqlIgnoreCase(d.name, dir_name)) {
                return d.allows(src);
            }
        }
        // Fallback to default-src
        for (self.directives.items) |d| {
            if (std.ascii.eqlIgnoreCase(d.name, "default-src")) {
                return d.allows(src);
            }
        }
        return true; // No policy restricts this directive
    }
};

test "csp parsing and script allowance" {
    const allocator = std.testing.allocator;
    const policy_str = "default-src 'self'; script-src 'self' https://cdn.davoth.org; img-src *";
    var csp = try ContentSecurityPolicy.parse(allocator, policy_str);
    defer csp.deinit();

    try std.testing.expect(csp.allowsScript("https://cdn.davoth.org"));
    try std.testing.expect(!csp.allowsScript("https://malicious-ads.com/script.js"));
}
