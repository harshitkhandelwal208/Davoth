//! Time utilities for Davoth.
const std = @import("std");

pub fn timestamp() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @as(i64, ts.sec);
}

pub fn milliTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

pub fn nanoTimestamp() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
}

test "milliTimestamp returns positive unix time" {
    const ts = milliTimestamp();
    try std.testing.expect(ts > 1_700_000_000_000); // Beyond year 2023 in milliseconds
}
