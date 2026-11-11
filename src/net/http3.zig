//! HTTP/3 and QUIC transport layer primitives.
const std = @import("std");

pub const QuicPacketType = enum(u8) {
    Initial = 0,
    ZeroRtt = 1,
    Handshake = 2,
    Retry = 3,
    OneRtt = 4, // Short header
};

pub const QuicPacketHeader = struct {
    packet_type: QuicPacketType,
    version: u32,
    dcid: []const u8,
    scid: []const u8,
    packet_number: u32,

    pub fn deserialize(bytes: []const u8) !QuicPacketHeader {
        if (bytes.len < 5) return error.PacketTooShort;
        const first = bytes[0];

        if ((first & 0x80) != 0) {
            // Long header
            const version = std.mem.readInt(u32, bytes[1..5], .big);
            const ptype_raw: u2 = @truncate((first >> 4) & 0x3);
            const ptype: QuicPacketType = @enumFromInt(ptype_raw);

            return QuicPacketHeader{
                .packet_type = ptype,
                .version = version,
                .dcid = "",
                .scid = "",
                .packet_number = 0,
            };
        } else {
            // Short header (1-RTT application data)
            return QuicPacketHeader{
                .packet_type = .OneRtt,
                .version = 1,
                .dcid = "",
                .scid = "",
                .packet_number = 0,
            };
        }
    }
};
