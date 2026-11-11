//! RFC 6455 WebSocket client protocol and frame masking.
const std = @import("std");

pub const WebSocketOpcode = enum(u4) {
    Continuation = 0x0,
    Text = 0x1,
    Binary = 0x2,
    Close = 0x8,
    Ping = 0x9,
    Pong = 0xA,
};

pub const WebSocketFrame = struct {
    fin: bool = true,
    opcode: WebSocketOpcode,
    masked: bool = true,
    mask_key: [4]u8 = [_]u8{ 0, 0, 0, 0 },
    payload: []const u8,

    pub fn serialize(self: WebSocketFrame, allocator: std.mem.Allocator) ![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        // Byte 1: FIN (1 bit) + RSV (3 bits) + Opcode (4 bits)
        var b1: u8 = @intFromEnum(self.opcode);
        if (self.fin) b1 |= 0x80;
        try list.append(allocator, b1);

        // Byte 2+: MASK (1 bit) + Payload len (7 / 7+16 / 7+64 bits)
        const mask_bit: u8 = if (self.masked) 0x80 else 0x00;
        if (self.payload.len < 126) {
            try list.append(allocator, mask_bit | @as(u8, @truncate(self.payload.len)));
        } else if (self.payload.len <= 0xFFFF) {
            try list.append(allocator, mask_bit | 126);
            var len_bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &len_bytes, @truncate(self.payload.len), .big);
            try list.appendSlice(allocator, &len_bytes);
        } else {
            try list.append(allocator, mask_bit | 127);
            var len_bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &len_bytes, self.payload.len, .big);
            try list.appendSlice(allocator, &len_bytes);
        }

        if (self.masked) {
            try list.appendSlice(allocator, &self.mask_key);
            // Apply mask to payload
            for (self.payload, 0..) |p, i| {
                const masked_byte = p ^ self.mask_key[i % 4];
                try list.append(allocator, masked_byte);
            }
        } else {
            try list.appendSlice(allocator, self.payload);
        }

        return list.toOwnedSlice(allocator);
    }
};

test "websocket frame serialization" {
    const allocator = std.testing.allocator;
    const frame = WebSocketFrame{
        .fin = true,
        .opcode = .Text,
        .masked = true,
        .mask_key = [4]u8{ 0x12, 0x34, 0x56, 0x78 },
        .payload = "Davoth",
    };

    const bytes = try frame.serialize(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0x81), bytes[0]); // FIN | Text
    try std.testing.expectEqual(@as(u8, 0x86), bytes[1]); // MASK | len 6
}
