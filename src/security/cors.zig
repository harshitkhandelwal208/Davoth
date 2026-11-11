//! Cross-Origin Resource Sharing (CORS) header verification and preflight checks.
const std = @import("std");
const Origin = @import("origin.zig").Origin;

pub const CorsCheckResult = enum {
    Allowed,
    Disallowed,
};

pub fn checkCorsResponse(origin: Origin, allow_origin_header: ?[]const u8) CorsCheckResult {
    const header = allow_origin_header orelse return .Disallowed;
    const trimmed = std.mem.trim(u8, header, " \t");

    if (std.mem.eql(u8, trimmed, "*")) {
        return .Allowed;
    }

    // Format origin string
    var orig_buf: [256]u8 = undefined;
    const orig_str = std.fmt.bufPrint(&orig_buf, "{s}://{s}", .{ origin.scheme, origin.host }) catch return .Disallowed;

    if (std.mem.eql(u8, trimmed, orig_str)) {
        return .Allowed;
    }

    return .Disallowed;
}

test "cors header check" {
    const o = Origin{ .scheme = "https", .host = "davoth.org", .port = 443 };
    try std.testing.expectEqual(CorsCheckResult.Allowed, checkCorsResponse(o, "*"));
    try std.testing.expectEqual(CorsCheckResult.Allowed, checkCorsResponse(o, "https://davoth.org"));
    try std.testing.expectEqual(CorsCheckResult.Disallowed, checkCorsResponse(o, "https://evil.com"));
    try std.testing.expectEqual(CorsCheckResult.Disallowed, checkCorsResponse(o, null));
}
