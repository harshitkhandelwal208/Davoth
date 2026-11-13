//! RFC 6455 WebSocket client protocol, full-duplex communication, frame masking,
//! serialization, deserialization, Ping/Pong keepalive, and fragmented frame reassembly.
const std = @import("std");
const URL = @import("../common/url.zig").URL;
const TLSStream = @import("tls.zig").TLSStream;
const DnsResolver = @import("dns.zig").DnsResolver;
const c = @import("../common/c.zig");

fn fillRandomBytes(buf: []u8) void {
    _ = c.RAND_bytes(buf.ptr, @intCast(buf.len));
}

pub const WebSocketOpcode = enum(u4) {
    Continuation = 0x0,
    Text = 0x1,
    Binary = 0x2,
    Close = 0x8,
    Ping = 0x9,
    Pong = 0xA,
};

pub const CloseCode = enum(u16) {
    NormalClosure = 1000,
    GoingAway = 1001,
    ProtocolError = 1002,
    UnsupportedData = 1003,
    PolicyViolation = 1008,
    MessageTooBig = 1009,
    InternalServerError = 1011,
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

pub const DeserializedFrame = struct {
    frame: WebSocketFrame,
    bytes_consumed: usize,
    owned_payload: bool = false,

    pub fn deinit(self: *DeserializedFrame, allocator: std.mem.Allocator) void {
        if (self.owned_payload and self.frame.payload.len > 0) {
            allocator.free(self.frame.payload);
        }
    }
};

pub const WebSocketMessage = struct {
    is_binary: bool,
    data: []const u8,

    pub fn deinit(self: *WebSocketMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub fn deserializeFrame(allocator: std.mem.Allocator, bytes: []const u8) !DeserializedFrame {
    if (bytes.len < 2) return error.IncompleteFrame;

    const b0 = bytes[0];
    const fin = (b0 & 0x80) != 0;
    const opcode_raw = b0 & 0x0F;
    const opcode: WebSocketOpcode = switch (opcode_raw) {
        0x0 => .Continuation,
        0x1 => .Text,
        0x2 => .Binary,
        0x8 => .Close,
        0x9 => .Ping,
        0xA => .Pong,
        else => return error.InvalidOpcode,
    };

    const b1 = bytes[1];
    const masked = (b1 & 0x80) != 0;
    const len_byte = b1 & 0x7F;

    var offset: usize = 2;
    var payload_len: usize = 0;

    if (len_byte < 126) {
        payload_len = len_byte;
    } else if (len_byte == 126) {
        if (bytes.len < offset + 2) return error.IncompleteFrame;
        payload_len = std.mem.readInt(u16, bytes[offset..][0..2], .big);
        offset += 2;
    } else if (len_byte == 127) {
        if (bytes.len < offset + 8) return error.IncompleteFrame;
        const len64 = std.mem.readInt(u64, bytes[offset..][0..8], .big);
        if (len64 > std.math.maxInt(usize)) return error.PayloadTooLarge;
        payload_len = @intCast(len64);
        offset += 8;
    }

    var mask_key: [4]u8 = [_]u8{ 0, 0, 0, 0 };
    if (masked) {
        if (bytes.len < offset + 4) return error.IncompleteFrame;
        @memcpy(&mask_key, bytes[offset .. offset + 4]);
        offset += 4;
    }

    if (bytes.len < offset + payload_len) return error.IncompleteFrame;

    const raw_payload = bytes[offset .. offset + payload_len];
    var out_payload: []u8 = undefined;

    if (masked) {
        out_payload = try allocator.alloc(u8, payload_len);
        for (raw_payload, 0..) |p, i| {
            out_payload[i] = p ^ mask_key[i % 4];
        }
    } else {
        out_payload = try allocator.dupe(u8, raw_payload);
    }

    return DeserializedFrame{
        .frame = .{
            .fin = fin,
            .opcode = opcode,
            .masked = masked,
            .mask_key = mask_key,
            .payload = out_payload,
        },
        .bytes_consumed = offset + payload_len,
        .owned_payload = true,
    };
}

pub fn computeAcceptKey(client_key: []const u8, out_accept: *[28]u8) !void {
    const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(client_key);
    hasher.update(GUID);
    var digest: [20]u8 = undefined;
    hasher.final(&digest);
    _ = std.base64.standard.Encoder.encode(out_accept, &digest);
}

pub const WebSocketClient = struct {
    allocator: std.mem.Allocator,
    dns: DnsResolver,
    tls_stream: ?TLSStream = null,
    sock_fd: ?std.posix.fd_t = null,
    is_tls: bool = false,
    connected: bool = false,
    read_buffer: std.ArrayList(u8),
    // Buffer for assembling fragmented continuation frames
    fragment_buffer: std.ArrayList(u8),
    current_fragment_opcode: ?WebSocketOpcode = null,
    // Egress queue for mock / duplex inspection
    sent_frames: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) WebSocketClient {
        return .{
            .allocator = allocator,
            .dns = DnsResolver.init(allocator),
            .read_buffer = .empty,
            .fragment_buffer = .empty,
            .sent_frames = .empty,
        };
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.close();
        self.dns.deinit();
        self.read_buffer.deinit(self.allocator);
        self.fragment_buffer.deinit(self.allocator);
        for (self.sent_frames.items) |f| {
            self.allocator.free(f);
        }
        self.sent_frames.deinit(self.allocator);
    }

    pub fn close(self: *WebSocketClient) void {
        if (self.is_tls) {
            if (self.tls_stream) |*t| {
                t.close();
                self.tls_stream = null;
            }
        } else {
            if (self.sock_fd) |fd| {
                _ = std.c.close(fd);
                self.sock_fd = null;
            }
        }
        self.connected = false;
    }

    pub fn connect(self: *WebSocketClient, url_str: []const u8) !void {
        var url = try URL.parse(self.allocator, url_str);
        defer url.deinit();

        const is_secure = std.mem.eql(u8, url.scheme, "wss") or std.mem.eql(u8, url.scheme, "https");
        self.is_tls = is_secure;

        const default_port: u16 = if (is_secure) 443 else 80;
        const port = if (url.port != 0) url.port else default_port;

        const ip = try self.dns.resolve(url.host);

        var nonce: [16]u8 = undefined;
        fillRandomBytes(&nonce);
        var sec_key: [24]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&sec_key, &nonce);

        var expected_accept: [28]u8 = undefined;
        try computeAcceptKey(&sec_key, &expected_accept);

        var req_buf: std.ArrayList(u8) = .empty;
        defer req_buf.deinit(self.allocator);

        try req_buf.appendSlice(self.allocator, "GET ");
        try req_buf.appendSlice(self.allocator, if (url.path.len > 0) url.path else "/");
        if (url.query) |q| {
            try req_buf.append(self.allocator, '?');
            try req_buf.appendSlice(self.allocator, q);
        }
        try req_buf.appendSlice(self.allocator, " HTTP/1.1\r\nHost: ");
        try req_buf.appendSlice(self.allocator, url.host);
        try req_buf.appendSlice(self.allocator, "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ");
        try req_buf.appendSlice(self.allocator, &sec_key);
        try req_buf.appendSlice(self.allocator, "\r\n\r\n");

        if (is_secure) {
            var tls = try TLSStream.connect(url.host, port, ip);
            _ = try tls.write(req_buf.items);
            self.tls_stream = tls;
        } else {
            const fd = std.c.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
            if (fd < 0) return error.SocketCreationFailed;
            self.sock_fd = fd;

            const sin_addr = @as(u32, ip[0]) |
                (@as(u32, ip[1]) << 8) |
                (@as(u32, ip[2]) << 16) |
                (@as(u32, ip[3]) << 24);

            const sock_addr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, port),
                .addr = sin_addr,
            };

            if (std.c.connect(fd, @ptrCast(&sock_addr), @sizeOf(std.posix.sockaddr.in)) != 0) {
                return error.ConnectionFailed;
            }

            _ = std.c.write(fd, req_buf.items.ptr, req_buf.items.len);
        }

        var resp_buf: [2048]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < resp_buf.len) {
            const n: usize = if (is_secure)
                try self.tls_stream.?.read(resp_buf[total_read..])
            else blk: {
                const res = std.c.read(self.sock_fd.?, resp_buf[total_read..].ptr, resp_buf.len - total_read);
                if (res <= 0) break :blk 0;
                break :blk @intCast(res);
            };

            if (n == 0) break;
            total_read += n;
            if (std.mem.indexOf(u8, resp_buf[0..total_read], "\r\n\r\n")) |_| break;
        }

        const resp_str = resp_buf[0..total_read];
        if (!std.mem.startsWith(u8, resp_str, "HTTP/1.1 101")) {
            return error.HandshakeFailed;
        }

        if (std.mem.indexOf(u8, resp_str, &expected_accept) == null) {
            return error.InvalidAcceptHeader;
        }

        self.connected = true;
    }

    /// Sends a raw WebSocket frame
    pub fn sendFrame(self: *WebSocketClient, frame: WebSocketFrame) !void {
        const bytes = try frame.serialize(self.allocator);
        defer self.allocator.free(bytes);

        // Keep copy for test inspection
        try self.sent_frames.append(self.allocator, try self.allocator.dupe(u8, bytes));

        if (self.connected) {
            if (self.is_tls and self.tls_stream != null) {
                _ = try self.tls_stream.?.write(bytes);
            } else if (self.sock_fd != null) {
                _ = std.c.write(self.sock_fd.?, bytes.ptr, bytes.len);
            }
        }
    }

    /// Sends a text or binary payload frame
    pub fn send(self: *WebSocketClient, text_or_binary: []const u8, is_binary: bool) !void {
        var mask_key: [4]u8 = undefined;
        fillRandomBytes(&mask_key);

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = if (is_binary) .Binary else .Text,
            .masked = true,
            .mask_key = mask_key,
            .payload = text_or_binary,
        };

        try self.sendFrame(frame);
    }

    /// Sends a Ping frame
    pub fn sendPing(self: *WebSocketClient, payload: []const u8) !void {
        var mask_key: [4]u8 = undefined;
        fillRandomBytes(&mask_key);

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = .Ping,
            .masked = true,
            .mask_key = mask_key,
            .payload = payload,
        };
        try self.sendFrame(frame);
    }

    /// Sends a Pong response frame
    pub fn sendPong(self: *WebSocketClient, payload: []const u8) !void {
        var mask_key: [4]u8 = undefined;
        fillRandomBytes(&mask_key);

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = .Pong,
            .masked = true,
            .mask_key = mask_key,
            .payload = payload,
        };
        try self.sendFrame(frame);
    }

    /// Sends a Close frame with RFC 6455 2-byte status code and reason
    pub fn sendClose(self: *WebSocketClient, code: CloseCode, reason: []const u8) !void {
        var payload_buf = std.ArrayList(u8).empty;
        defer payload_buf.deinit(self.allocator);

        var code_bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &code_bytes, @intFromEnum(code), .big);
        try payload_buf.appendSlice(self.allocator, &code_bytes);
        try payload_buf.appendSlice(self.allocator, reason);

        var mask_key: [4]u8 = undefined;
        fillRandomBytes(&mask_key);

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = .Close,
            .masked = true,
            .mask_key = mask_key,
            .payload = payload_buf.items,
        };
        try self.sendFrame(frame);
        self.connected = false;
    }

    /// Feeds incoming raw bytes into the read buffer
    pub fn feedIncomingBytes(self: *WebSocketClient, data: []const u8) !void {
        try self.read_buffer.appendSlice(self.allocator, data);
    }

    /// Full-duplex message processor: handles incoming frames, automated Ping->Pong replies,
    /// Close frame negotiation, and multi-frame continuation reassembly.
    pub fn receiveMessage(self: *WebSocketClient) !?WebSocketMessage {
        while (self.read_buffer.items.len >= 2) {
            var des = deserializeFrame(self.allocator, self.read_buffer.items) catch |err| {
                if (err == error.IncompleteFrame) return null;
                return err;
            };
            defer des.deinit(self.allocator);

            // Consume the deserialized frame bytes from the read buffer
            const consumed = des.bytes_consumed;
            const remaining = self.read_buffer.items.len - consumed;
            if (remaining > 0) {
                std.mem.copyForwards(u8, self.read_buffer.items[0..remaining], self.read_buffer.items[consumed..]);
            }
            self.read_buffer.items.len = remaining;

            switch (des.frame.opcode) {
                .Ping => {
                    // RFC 6455: Upon receipt of a Ping frame, an endpoint MUST send a Pong frame in response
                    try self.sendPong(des.frame.payload);
                    continue;
                },
                .Pong => {
                    // Unsolicited or solicited Pong, continue
                    continue;
                },
                .Close => {
                    // Send Close response if connected
                    if (self.connected) {
                        try self.sendClose(.NormalClosure, "");
                    }
                    self.connected = false;
                    return null;
                },
                .Text, .Binary => {
                    if (des.frame.fin) {
                        // Single complete unfragmented frame
                        const is_bin = des.frame.opcode == .Binary;
                        return WebSocketMessage{
                            .is_binary = is_bin,
                            .data = try self.allocator.dupe(u8, des.frame.payload),
                        };
                    } else {
                        // First fragment of fragmented message
                        self.fragment_buffer.clearRetainingCapacity();
                        try self.fragment_buffer.appendSlice(self.allocator, des.frame.payload);
                        self.current_fragment_opcode = des.frame.opcode;
                        continue;
                    }
                },
                .Continuation => {
                    // Continuation frame of fragmented message
                    try self.fragment_buffer.appendSlice(self.allocator, des.frame.payload);
                    if (des.frame.fin) {
                        const is_bin = (self.current_fragment_opcode orelse .Text) == .Binary;
                        const assembled = try self.fragment_buffer.toOwnedSlice(self.allocator);
                        self.current_fragment_opcode = null;
                        return WebSocketMessage{
                            .is_binary = is_bin,
                            .data = assembled,
                        };
                    }
                    continue;
                },
            }
        }

        return null;
    }
};

test "websocket frame serialization and deserialization roundtrip" {
    const allocator = std.testing.allocator;
    const original_text = "Davoth Web Platform WebSocket Communication Layer";
    const mask = [4]u8{ 0x3a, 0x7b, 0x9c, 0x1f };

    const frame = WebSocketFrame{
        .fin = true,
        .opcode = .Text,
        .masked = true,
        .mask_key = mask,
        .payload = original_text,
    };

    const bytes = try frame.serialize(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0x81), bytes[0]); // FIN | Text

    var des = try deserializeFrame(allocator, bytes);
    defer des.deinit(allocator);

    try std.testing.expectEqual(true, des.frame.fin);
    try std.testing.expectEqual(WebSocketOpcode.Text, des.frame.opcode);
    try std.testing.expectEqualStrings(original_text, des.frame.payload);
    try std.testing.expectEqual(bytes.len, des.bytes_consumed);
}

test "rfc 6455 section 1.3 handshake accept computation" {
    const rfc_key = "dGhlIHNhbXBsZSBub25jZQ==";
    const expected_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";

    var accept_buf: [28]u8 = undefined;
    try computeAcceptKey(rfc_key, &accept_buf);

    try std.testing.expectEqualStrings(expected_accept, &accept_buf);
}

test "websocket client automated ping-pong response and close negotiation" {
    const allocator = std.testing.allocator;
    var client = WebSocketClient.init(allocator);
    defer client.deinit();

    // 1. Simulate incoming Ping from server
    const ping_frame = WebSocketFrame{
        .fin = true,
        .opcode = .Ping,
        .masked = false,
        .payload = "keepalive-token-987",
    };
    const ping_bytes = try ping_frame.serialize(allocator);
    defer allocator.free(ping_bytes);

    try client.feedIncomingBytes(ping_bytes);

    // Process message loop -> should automatically generate Pong response
    const msg = try client.receiveMessage();
    try std.testing.expect(msg == null); // Ping does not return user message
    try std.testing.expectEqual(@as(usize, 1), client.sent_frames.items.len);

    // Verify generated Pong frame
    var pong_des = try deserializeFrame(allocator, client.sent_frames.items[0]);
    defer pong_des.deinit(allocator);
    try std.testing.expectEqual(WebSocketOpcode.Pong, pong_des.frame.opcode);
    try std.testing.expectEqualStrings("keepalive-token-987", pong_des.frame.payload);

    // 2. Simulate incoming Close frame from server
    var close_payload: [2]u8 = undefined;
    std.mem.writeInt(u16, &close_payload, 1000, .big);
    const close_frame = WebSocketFrame{
        .fin = true,
        .opcode = .Close,
        .masked = false,
        .payload = &close_payload,
    };
    const close_bytes = try close_frame.serialize(allocator);
    defer allocator.free(close_bytes);

    try client.feedIncomingBytes(close_bytes);
    const close_res = try client.receiveMessage();
    try std.testing.expect(close_res == null);
    try std.testing.expect(!client.connected);
}

test "websocket client continuation frame defragmentation" {
    const allocator = std.testing.allocator;
    var client = WebSocketClient.init(allocator);
    defer client.deinit();

    // Segment 1: FIN=false, Opcode=Text
    const part1 = WebSocketFrame{
        .fin = false,
        .opcode = .Text,
        .masked = false,
        .payload = "Part 1 of message -- ",
    };
    const b1 = try part1.serialize(allocator);
    defer allocator.free(b1);
    try client.feedIncomingBytes(b1);

    // Receiving now returns null because message is not finished
    const mid = try client.receiveMessage();
    try std.testing.expect(mid == null);

    // Segment 2: FIN=true, Opcode=Continuation
    const part2 = WebSocketFrame{
        .fin = true,
        .opcode = .Continuation,
        .masked = false,
        .payload = "Part 2 complete!",
    };
    const b2 = try part2.serialize(allocator);
    defer allocator.free(b2);
    try client.feedIncomingBytes(b2);

    // Full message is assembled
    var full = (try client.receiveMessage()).?;
    defer full.deinit(allocator);

    try std.testing.expectEqual(false, full.is_binary);
    try std.testing.expectEqualStrings("Part 1 of message -- Part 2 complete!", full.data);
}
