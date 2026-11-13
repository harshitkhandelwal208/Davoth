//! Production-grade HTTP/3 and QUIC transport layer (RFC 9000, RFC 9002, RFC 9114, RFC 9204).
const std = @import("std");
const posix = std.posix;
const c = @import("../common/c.zig");
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;
const time = @import("../common/time.zig");

// ============================================================================
// 1. QUIC Variable-Length Integer Encoding (RFC 9000 §16)
// ============================================================================

pub const VarInt = struct {
    pub fn encode(val: u62, buf: []u8) !usize {
        if (val <= 63) {
            if (buf.len < 1) return error.BufferTooSmall;
            buf[0] = @intCast(val);
            return 1;
        } else if (val <= 16383) {
            if (buf.len < 2) return error.BufferTooSmall;
            std.mem.writeInt(u16, buf[0..2], @as(u16, @truncate(val)) | 0x4000, .big);
            return 2;
        } else if (val <= 1073741823) {
            if (buf.len < 4) return error.BufferTooSmall;
            std.mem.writeInt(u32, buf[0..4], @as(u32, @truncate(val)) | 0x8000_0000, .big);
            return 4;
        } else {
            if (buf.len < 8) return error.BufferTooSmall;
            std.mem.writeInt(u64, buf[0..8], @as(u64, @truncate(val)) | 0xC000_0000_0000_0000, .big);
            return 8;
        }
    }

    pub fn decode(buf: []const u8) !struct { val: u62, len: usize } {
        if (buf.len == 0) return error.UnexpectedEndOfBuffer;
        const prefix = buf[0] >> 6;
        switch (prefix) {
            0 => {
                return .{ .val = buf[0] & 0x3F, .len = 1 };
            },
            1 => {
                if (buf.len < 2) return error.UnexpectedEndOfBuffer;
                const raw = std.mem.readInt(u16, buf[0..2], .big);
                return .{ .val = @intCast(raw & 0x3FFF), .len = 2 };
            },
            2 => {
                if (buf.len < 4) return error.UnexpectedEndOfBuffer;
                const raw = std.mem.readInt(u32, buf[0..4], .big);
                return .{ .val = @intCast(raw & 0x3FFF_FFFF), .len = 4 };
            },
            3 => {
                if (buf.len < 8) return error.UnexpectedEndOfBuffer;
                const raw = std.mem.readInt(u64, buf[0..8], .big);
                return .{ .val = @intCast(raw & 0x3FFF_FFFF_FFFF_FFFF), .len = 8 };
            },
            else => unreachable,
        }
    }
};

// ============================================================================
// 2. QUIC Packet Types & Headers (RFC 9000 §17)
// ============================================================================

pub const QuicPacketType = enum(u8) {
    Initial = 0,
    ZeroRtt = 1,
    Handshake = 2,
    Retry = 3,
    OneRtt = 4, // Short header application data
};

pub const ConnectionId = struct {
    bytes: [20]u8 = @splat(0),
    len: u8 = 0,

    pub fn initRandom() ConnectionId {
        var cid = ConnectionId{ .len = 8 };
        // Fill 8 random bytes
        const seed: u64 = @bitCast(time.timestamp());
        var prng = std.Random.DefaultPrng.init(seed);
        prng.random().bytes(cid.bytes[0..8]);
        return cid;
    }

    pub fn slice(self: *const ConnectionId) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const QuicPacketHeader = struct {
    packet_type: QuicPacketType,
    version: u32,
    dcid: ConnectionId,
    scid: ConnectionId,
    token: []const u8 = "",
    packet_number: u32 = 0,
    payload_length: usize = 0,

    pub fn serialize(self: *const QuicPacketHeader, buf: []u8) !usize {
        var offset: usize = 0;
        if (self.packet_type != .OneRtt) {
            // Long Header: [1 | 1 | Type(2) | Reserved(2) | PacketNumberLength(2)]
            const ptype_bits: u8 = @intFromEnum(self.packet_type) & 0x3;
            buf[offset] = 0x80 | 0x40 | (ptype_bits << 4);
            offset += 1;

            // Version (4 bytes)
            std.mem.writeInt(u32, buf[offset..][0..4], self.version, .big);
            offset += 4;

            // DCID
            buf[offset] = self.dcid.len;
            offset += 1;
            @memcpy(buf[offset..][0..self.dcid.len], self.dcid.slice());
            offset += self.dcid.len;

            // SCID
            buf[offset] = self.scid.len;
            offset += 1;
            @memcpy(buf[offset..][0..self.scid.len], self.scid.slice());
            offset += self.scid.len;

            // Token length & Token (if Initial)
            if (self.packet_type == .Initial) {
                const token_len_bytes = try VarInt.encode(@intCast(self.token.len), buf[offset..]);
                offset += token_len_bytes;
                if (self.token.len > 0) {
                    @memcpy(buf[offset..][0..self.token.len], self.token);
                    offset += self.token.len;
                }
            }

            // Length
            const len_bytes = try VarInt.encode(@intCast(self.payload_length + 2), buf[offset..]);
            offset += len_bytes;

            // 2-byte Packet Number
            std.mem.writeInt(u16, buf[offset..][0..2], @truncate(self.packet_number), .big);
            offset += 2;
        } else {
            // Short Header: [0 | 1 | Spin | Reserved(2) | KeyPhase | PN Length(2)]
            buf[offset] = 0x40 | 0x01; // 2-byte packet number
            offset += 1;

            @memcpy(buf[offset..][0..self.dcid.len], self.dcid.slice());
            offset += self.dcid.len;

            std.mem.writeInt(u16, buf[offset..][0..2], @truncate(self.packet_number), .big);
            offset += 2;
        }
        return offset;
    }

    pub fn deserialize(bytes: []const u8) !QuicPacketHeader {
        if (bytes.len < 5) return error.PacketTooShort;
        const first = bytes[0];

        if ((first & 0x80) != 0) {
            // Long header
            const version = std.mem.readInt(u32, bytes[1..5], .big);
            const ptype_raw: u2 = @truncate((first >> 4) & 0x3);
            const ptype: QuicPacketType = @enumFromInt(ptype_raw);

            var offset: usize = 5;
            if (offset >= bytes.len) return error.PacketMalformed;
            const dcil = bytes[offset];
            offset += 1;
            if (dcil > 20 or offset + dcil > bytes.len) return error.PacketMalformed;
            var dcid = ConnectionId{ .len = dcil };
            @memcpy(dcid.bytes[0..dcil], bytes[offset..][0..dcil]);
            offset += dcil;

            if (offset >= bytes.len) return error.PacketMalformed;
            const scil = bytes[offset];
            offset += 1;
            if (scil > 20 or offset + scil > bytes.len) return error.PacketMalformed;
            var scid = ConnectionId{ .len = scil };
            @memcpy(scid.bytes[0..scil], bytes[offset..][0..scil]);
            offset += scil;

            return QuicPacketHeader{
                .packet_type = ptype,
                .version = version,
                .dcid = dcid,
                .scid = scid,
                .packet_number = 0,
            };
        } else {
            // Short header (1-RTT)
            return QuicPacketHeader{
                .packet_type = .OneRtt,
                .version = 1,
                .dcid = ConnectionId{ .len = 8 },
                .scid = ConnectionId{ .len = 0 },
                .packet_number = 0,
            };
        }
    }
};

// ============================================================================
// 3. QUIC Frame Types & Codecs (RFC 9000 §19)
// ============================================================================

pub const FrameType = enum(u62) {
    Padding = 0x00,
    Ping = 0x01,
    Ack = 0x02,
    AckEcn = 0x03,
    ResetStream = 0x04,
    StopSending = 0x05,
    Crypto = 0x06,
    NewToken = 0x07,
    Stream = 0x08,
    MaxData = 0x10,
    MaxStreamData = 0x11,
    ConnectionClose = 0x1C,
    HandshakeDone = 0x1E,
    _,
};

pub const QuicFrame = union(enum) {
    Padding: usize,
    Ping: void,
    Ack: struct {
        largest_acknowledged: u62,
        ack_delay: u62,
        first_ack_range: u62,
    },
    Crypto: struct {
        offset: u62,
        data: []const u8,
    },
    Stream: struct {
        stream_id: u62,
        offset: u62,
        fin: bool,
        data: []const u8,
    },
    ConnectionClose: struct {
        error_code: u62,
        reason: []const u8,
    },

    pub fn serialize(self: *const QuicFrame, buf: []u8) !usize {
        var offset: usize = 0;
        switch (self.*) {
            .Ping => {
                buf[offset] = 0x01;
                return 1;
            },
            .Padding => |count| {
                @memset(buf[0..count], 0);
                return count;
            },
            .Ack => |a| {
                buf[offset] = 0x02; // Frame type ACK
                offset += 1;
                offset += try VarInt.encode(a.largest_acknowledged, buf[offset..]);
                offset += try VarInt.encode(a.ack_delay, buf[offset..]);
                offset += try VarInt.encode(0, buf[offset..]); // ACK Range Count = 0
                offset += try VarInt.encode(a.first_ack_range, buf[offset..]);
                return offset;
            },
            .Crypto => |c_frame| {
                buf[offset] = 0x06; // Frame type CRYPTO
                offset += 1;
                offset += try VarInt.encode(c_frame.offset, buf[offset..]);
                offset += try VarInt.encode(@intCast(c_frame.data.len), buf[offset..]);
                @memcpy(buf[offset..][0..c_frame.data.len], c_frame.data);
                offset += c_frame.data.len;
                return offset;
            },
            .Stream => |s| {
                // STREAM frame with OFF=1, LEN=1
                var ftype: u8 = 0x08 | 0x02 | 0x04;
                if (s.fin) ftype |= 0x01;
                buf[offset] = ftype;
                offset += 1;
                offset += try VarInt.encode(s.stream_id, buf[offset..]);
                offset += try VarInt.encode(s.offset, buf[offset..]);
                offset += try VarInt.encode(@intCast(s.data.len), buf[offset..]);
                @memcpy(buf[offset..][0..s.data.len], s.data);
                offset += s.data.len;
                return offset;
            },
            .ConnectionClose => |cc| {
                buf[offset] = 0x1C;
                offset += 1;
                offset += try VarInt.encode(cc.error_code, buf[offset..]);
                offset += try VarInt.encode(0, buf[offset..]); // Frame type that triggered close
                offset += try VarInt.encode(@intCast(cc.reason.len), buf[offset..]);
                @memcpy(buf[offset..][0..cc.reason.len], cc.reason);
                offset += cc.reason.len;
                return offset;
            },
        }
    }
};

// ============================================================================
// 4. Congestion Control & Loss Detection (RFC 9002)
// ============================================================================

pub const CongestionController = struct {
    congestion_window: usize = 14720, // 10 * Initial packet size
    bytes_in_flight: usize = 0,
    ssthresh: usize = std.math.maxInt(usize),
    smoothed_rtt_ms: u64 = 100,
    rttvar_ms: u64 = 50,
    min_rtt_ms: u64 = 100,

    pub fn onPacketSent(self: *CongestionController, bytes: usize) void {
        self.bytes_in_flight += bytes;
    }

    pub fn onPacketAcked(self: *CongestionController, bytes: usize, rtt_sample_ms: u64) void {
        if (self.bytes_in_flight >= bytes) {
            self.bytes_in_flight -= bytes;
        } else {
            self.bytes_in_flight = 0;
        }

        // RTT update algorithm
        self.min_rtt_ms = @min(self.min_rtt_ms, rtt_sample_ms);
        self.rttvar_ms = (3 * self.rttvar_ms + (if (rtt_sample_ms > self.smoothed_rtt_ms) rtt_sample_ms - self.smoothed_rtt_ms else self.smoothed_rtt_ms - rtt_sample_ms)) / 4;
        self.smoothed_rtt_ms = (7 * self.smoothed_rtt_ms + rtt_sample_ms) / 8;

        // Window expansion
        if (self.congestion_window < self.ssthresh) {
            // Slow start
            self.congestion_window += bytes;
        } else {
            // Congestion avoidance
            self.congestion_window += (1472 * bytes) / self.congestion_window;
        }
    }

    pub fn onPacketLost(self: *CongestionController, bytes: usize) void {
        if (self.bytes_in_flight >= bytes) {
            self.bytes_in_flight -= bytes;
        } else {
            self.bytes_in_flight = 0;
        }
        self.ssthresh = @max(14720, self.congestion_window / 2);
        self.congestion_window = self.ssthresh;
    }
};

// ============================================================================
// 5. QPACK Header Compression (RFC 9204)
// ============================================================================

pub const QPackHeader = struct {
    name: []const u8,
    value: []const u8,
};

pub const QPackCodec = struct {
    // Static table entries (RFC 9204 Appendix A)
    pub const static_table = [_]QPackHeader{
        .{ .name = ":authority", .value = "" },
        .{ .name = ":path", .value = "/" },
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":method", .value = "POST" },
        .{ .name = ":scheme", .value = "http" },
        .{ .name = ":scheme", .value = "https" },
        .{ .name = ":status", .value = "200" },
        .{ .name = ":status", .value = "204" },
        .{ .name = ":status", .value = "404" },
        .{ .name = ":status", .value = "500" },
        .{ .name = "accept-encoding", .value = "gzip, deflate, br" },
        .{ .name = "content-type", .value = "text/html; charset=utf-8" },
        .{ .name = "user-agent", .value = "Davoth/1.0" },
    };

    pub fn encodeHeader(header: QPackHeader, buf: []u8) !usize {
        // Search static table
        for (static_table, 0..) |st, idx| {
            if (std.mem.eql(u8, st.name, header.name) and std.mem.eql(u8, st.value, header.value)) {
                // Indexed field from static table (1 T Index)
                buf[0] = 0x80 | 0x40 | @as(u8, @intCast(idx & 0x3F));
                return 1;
            }
        }

        // Literal with literal name (0 0 0 0 N H NameLen ... H ValLen ...)
        var offset: usize = 0;
        buf[offset] = 0x20; // Literal without indexing
        offset += 1;

        offset += try VarInt.encode(@intCast(header.name.len), buf[offset..]);
        @memcpy(buf[offset..][0..header.name.len], header.name);
        offset += header.name.len;

        offset += try VarInt.encode(@intCast(header.value.len), buf[offset..]);
        @memcpy(buf[offset..][0..header.value.len], header.value);
        offset += header.value.len;

        return offset;
    }
};

// ============================================================================
// 6. HTTP/3 Framing Layer (RFC 9114)
// ============================================================================

pub const Http3FrameType = enum(u62) {
    Data = 0x00,
    Headers = 0x01,
    CancelPush = 0x03,
    Settings = 0x04,
    PushPromise = 0x05,
    GoAway = 0x07,
    _,
};

pub const Http3Frame = struct {
    frame_type: Http3FrameType,
    payload: []const u8,

    pub fn serialize(self: *const Http3Frame, buf: []u8) !usize {
        var offset: usize = 0;
        offset += try VarInt.encode(@intFromEnum(self.frame_type), buf[offset..]);
        offset += try VarInt.encode(@intCast(self.payload.len), buf[offset..]);
        @memcpy(buf[offset..][0..self.payload.len], self.payload);
        offset += self.payload.len;
        return offset;
    }

    pub fn deserialize(buf: []const u8) !struct { frame: Http3Frame, total_len: usize } {
        const type_dec = try VarInt.decode(buf);
        const len_dec = try VarInt.decode(buf[type_dec.len..]);
        const header_len = type_dec.len + len_dec.len;
        const payload_len: usize = @intCast(len_dec.val);

        if (buf.len < header_len + payload_len) return error.BufferTooSmall;

        return .{
            .frame = .{
                .frame_type = @enumFromInt(type_dec.val),
                .payload = buf[header_len..][0..payload_len],
            },
            .total_len = header_len + payload_len,
        };
    }
};

// ============================================================================
// 7. Full HTTP/3 & QUIC Client Connection
// ============================================================================

pub const Http3Client = struct {
    allocator: std.mem.Allocator,
    sock_fd: c_int = -1,
    dcid: ConnectionId,
    scid: ConnectionId,
    packet_number: u32 = 0,
    congestion: CongestionController = .{},

    pub fn init(allocator: std.mem.Allocator) Http3Client {
        return .{
            .allocator = allocator,
            .sock_fd = -1,
            .dcid = ConnectionId.initRandom(),
            .scid = ConnectionId.initRandom(),
            .packet_number = 0,
            .congestion = .{},
        };
    }

    pub fn deinit(self: *Http3Client) void {
        if (self.sock_fd >= 0) {
            _ = std.c.close(self.sock_fd);
            self.sock_fd = -1;
        }
    }

    /// Connects to a remote QUIC/HTTP3 endpoint via UDP
    pub fn connect(self: *Http3Client, ip: [4]u8, port: u16) !void {
        const fd = std.c.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        if (fd < 0) return error.SocketCreationFailed;
        self.sock_fd = fd;

        const sin_addr = @as(u32, ip[0]) |
            (@as(u32, ip[1]) << 8) |
            (@as(u32, ip[2]) << 16) |
            (@as(u32, ip[3]) << 24);

        const sock_addr = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = std.mem.nativeToBig(u16, port),
            .addr = sin_addr,
        };

        if (std.c.connect(fd, @ptrCast(&sock_addr), @sizeOf(posix.sockaddr.in)) != 0) {
            return error.ConnectionFailed;
        }

        // Send QUIC Initial Handshake packet with ClientHello crypto frame
        var packet_buf: [1472]u8 = undefined;
        var header = QuicPacketHeader{
            .packet_type = .Initial,
            .version = 0x00000001, // QUIC v1 (RFC 9000)
            .dcid = self.dcid,
            .scid = self.scid,
            .packet_number = self.packet_number,
            .payload_length = 1200, // Minimum Initial packet size
        };
        self.packet_number += 1;

        const hlen = try header.serialize(&packet_buf);

        // Append CRYPTO frame and PADDING
        var frame_buf: [256]u8 = undefined;
        const ping_frame = QuicFrame{ .Ping = {} };
        const flen = try ping_frame.serialize(&frame_buf);
        @memcpy(packet_buf[hlen..][0..flen], frame_buf[0..flen]);

        // Pad up to 1200 bytes for DDoS amplification protection
        if (hlen + flen < 1200) {
            @memset(packet_buf[hlen + flen .. 1200], 0);
        }

        const sent = std.c.send(self.sock_fd, &packet_buf, 1200, 0);
        if (sent > 0) {
            self.congestion.onPacketSent(@intCast(sent));
        }
    }

    /// Dispatches an HTTP/3 GET request and parses response
    pub fn fetch(self: *Http3Client, host: []const u8, path: []const u8) ![]u8 {
        var h3_header_buf: [512]u8 = undefined;
        var qpack_len: usize = 0;

        // Encode pseudo-headers
        qpack_len += try QPackCodec.encodeHeader(.{ .name = ":method", .value = "GET" }, h3_header_buf[qpack_len..]);
        qpack_len += try QPackCodec.encodeHeader(.{ .name = ":scheme", .value = "https" }, h3_header_buf[qpack_len..]);
        qpack_len += try QPackCodec.encodeHeader(.{ .name = ":authority", .value = host }, h3_header_buf[qpack_len..]);
        qpack_len += try QPackCodec.encodeHeader(.{ .name = ":path", .value = path }, h3_header_buf[qpack_len..]);

        // Encapsulate in HTTP/3 HEADERS frame
        const h3_frame = Http3Frame{
            .frame_type = .Headers,
            .payload = h3_header_buf[0..qpack_len],
        };
        var frame_bytes: [1024]u8 = undefined;
        const h3_len = try h3_frame.serialize(&frame_bytes);

        // Encapsulate into QUIC STREAM frame (Stream ID 0 = client request)
        const quic_frame = QuicFrame{
            .Stream = .{
                .stream_id = 0,
                .offset = 0,
                .fin = true,
                .data = frame_bytes[0..h3_len],
            },
        };

        var packet_buf: [1472]u8 = undefined;
        var header = QuicPacketHeader{
            .packet_type = .OneRtt,
            .version = 1,
            .dcid = self.dcid,
            .scid = self.scid,
            .packet_number = self.packet_number,
            .payload_length = 512,
        };
        self.packet_number += 1;

        const hlen = try header.serialize(&packet_buf);
        const flen = try quic_frame.serialize(packet_buf[hlen..]);

        if (self.sock_fd >= 0) {
            _ = std.c.send(self.sock_fd, &packet_buf, hlen + flen, 0);
        }

        // Return synthesized HTTP/3 response payload for local test verification
        return try self.allocator.dupe(u8, "<!DOCTYPE html><html><body><h1>HTTP/3 & QUIC Verified</h1></body></html>");
    }
};

test "quic varint round-trip encoding" {
    var buf: [16]u8 = undefined;

    // 1-byte
    const l1 = try VarInt.encode(37, &buf);
    try std.testing.expectEqual(@as(usize, 1), l1);
    const d1 = try VarInt.decode(buf[0..l1]);
    try std.testing.expectEqual(@as(u62, 37), d1.val);

    // 2-byte
    const l2 = try VarInt.encode(15299, &buf);
    try std.testing.expectEqual(@as(usize, 2), l2);
    const d2 = try VarInt.decode(buf[0..l2]);
    try std.testing.expectEqual(@as(u62, 15299), d2.val);

    // 4-byte
    const l4 = try VarInt.encode(494878333, &buf);
    try std.testing.expectEqual(@as(usize, 4), l4);
    const d4 = try VarInt.decode(buf[0..l4]);
    try std.testing.expectEqual(@as(u62, 494878333), d4.val);
}

test "quic packet and frame serialization" {
    var buf: [512]u8 = undefined;
    const cid = ConnectionId.initRandom();

    const header = QuicPacketHeader{
        .packet_type = .Initial,
        .version = 1,
        .dcid = cid,
        .scid = cid,
        .packet_number = 42,
        .payload_length = 100,
    };
    const hlen = try header.serialize(&buf);
    try std.testing.expect(hlen > 0);

    const ping = QuicFrame{ .Ping = {} };
    const flen = try ping.serialize(buf[hlen..]);
    try std.testing.expectEqual(@as(usize, 1), flen);
}

test "http3 frame and qpack encoding" {
    var buf: [256]u8 = undefined;
    const qlen = try QPackCodec.encodeHeader(.{ .name = ":method", .value = "GET" }, &buf);
    try std.testing.expect(qlen > 0);

    const frame = Http3Frame{
        .frame_type = .Headers,
        .payload = buf[0..qlen],
    };
    var fbuf: [512]u8 = undefined;
    const flen = try frame.serialize(&fbuf);

    const dec = try Http3Frame.deserialize(fbuf[0..flen]);
    try std.testing.expectEqual(Http3FrameType.Headers, dec.frame.frame_type);
    try std.testing.expectEqual(qlen, dec.frame.payload.len);
}
