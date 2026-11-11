//! HTTP/2 binary framing and HPACK static table decoder.
const std = @import("std");

pub const FrameType = enum(u8) {
    Data = 0,
    Headers = 1,
    Priority = 2,
    RstStream = 3,
    Settings = 4,
    PushPromise = 5,
    Ping = 6,
    GoAway = 7,
    WindowUpdate = 8,
    Continuation = 9,
};

pub const FrameHeader = struct {
    length: u24,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31,

    pub fn serialize(self: FrameHeader, out: *[9]u8) void {
        out[0] = @truncate((self.length >> 16) & 0xFF);
        out[1] = @truncate((self.length >> 8) & 0xFF);
        out[2] = @truncate(self.length & 0xFF);
        out[3] = @intFromEnum(self.frame_type);
        out[4] = self.flags;
        std.mem.writeInt(u32, out[5..9], self.stream_id, .big);
    }

    pub fn deserialize(bytes: *const [9]u8) FrameHeader {
        const len: u24 = (@as(u24, bytes[0]) << 16) | (@as(u24, bytes[1]) << 8) | @as(u24, bytes[2]);
        const ftype: FrameType = @enumFromInt(bytes[3]);
        const flags = bytes[4];
        const stream_id: u31 = @truncate(std.mem.readInt(u32, bytes[5..9], .big) & 0x7FFF_FFFF);

        return .{
            .length = len,
            .frame_type = ftype,
            .flags = flags,
            .stream_id = stream_id,
        };
    }
};

pub const HpackStaticEntry = struct {
    name: []const u8,
    value: []const u8,
};

pub const HPACK_STATIC_TABLE = [_]HpackStaticEntry{
    .{ .name = ":authority", .value = "" },
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":method", .value = "POST" },
    .{ .name = ":path", .value = "/" },
    .{ .name = ":path", .value = "/index.html" },
    .{ .name = ":scheme", .value = "http" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":status", .value = "200" },
    .{ .name = ":status", .value = "204" },
    .{ .name = ":status", .value = "206" },
    .{ .name = ":status", .value = "304" },
    .{ .name = ":status", .value = "400" },
    .{ .name = ":status", .value = "404" },
    .{ .name = ":status", .value = "500" },
    .{ .name = "accept-charset", .value = "" },
    .{ .name = "accept-encoding", .value = "gzip, deflate" },
    .{ .name = "accept-language", .value = "" },
    .{ .name = "accept-ranges", .value = "" },
    .{ .name = "accept", .value = "" },
    .{ .name = "access-control-allow-origin", .value = "" },
};

test "http2 frame header serialization" {
    const original = FrameHeader{
        .length = 128,
        .frame_type = .Settings,
        .flags = 1,
        .stream_id = 0,
    };

    var buf: [9]u8 = undefined;
    original.serialize(&buf);

    const parsed = FrameHeader.deserialize(&buf);
    try std.testing.expectEqual(original.length, parsed.length);
    try std.testing.expectEqual(original.frame_type, parsed.frame_type);
    try std.testing.expectEqual(original.flags, parsed.flags);
    try std.testing.expectEqual(original.stream_id, parsed.stream_id);
}
