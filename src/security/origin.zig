//! Same-Origin Policy (SOP) calculation and origin abstractions.
const std = @import("std");
const URL = @import("../common/url.zig").URL;

pub const Origin = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    is_opaque: bool = false,

    pub fn fromUrl(url: *const URL) Origin {
        return .{
            .scheme = url.scheme,
            .host = url.host,
            .port = url.port,
            .is_opaque = false,
        };
    }

    pub fn opaqueOrigin() Origin {
        return .{
            .scheme = "",
            .host = "",
            .port = 0,
            .is_opaque = true,
        };
    }

    pub fn isSameOrigin(self: Origin, other: Origin) bool {
        if (self.is_opaque or other.is_opaque) return false;
        return std.mem.eql(u8, self.scheme, other.scheme) and
            std.mem.eql(u8, self.host, other.host) and
            self.port == other.port;
    }
};

test "origin same origin policy" {
    const allocator = std.testing.allocator;
    var url1 = try URL.parse(allocator, "https://davoth.org:443/page1");
    defer url1.deinit();
    var url2 = try URL.parse(allocator, "https://davoth.org:443/page2");
    defer url2.deinit();
    var url3 = try URL.parse(allocator, "http://davoth.org:80/page1");
    defer url3.deinit();

    const o1 = Origin.fromUrl(&url1);
    const o2 = Origin.fromUrl(&url2);
    const o3 = Origin.fromUrl(&url3);

    try std.testing.expect(o1.isSameOrigin(o2));
    try std.testing.expect(!o1.isSameOrigin(o3)); // different scheme
}
