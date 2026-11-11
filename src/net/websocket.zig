//! RFC 6455 WebSocket client protocol, frame masking, serialization, deserialization, and handshake.
const std = @import("std");
const URL = @import("../common/url.zig").URL;
const TLSStream = @import("tls.zig").TLSStream;
const DnsResolver = @import("dns.zig").DnsResolver;

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
        payload_len = std.mem.readInt(u16, bytes[offset .. offset + 2], .big);
        offset += 2;
    } else if (len_byte == 127) {
        if (bytes.len < offset + 8) return error.IncompleteFrame;
        const len64 = std.mem.readInt(u64, bytes[offset .. offset + 8], .big);
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

    pub fn init(allocator: std.mem.Allocator) WebSocketClient {
        return .{
            .allocator = allocator,
            .dns = DnsResolver.init(allocator),
            .read_buffer = .empty,
        };
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.close();
        self.dns.deinit();
        self.read_buffer.deinit(self.allocator);
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
        std.crypto.random.bytes(&nonce);
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

    pub fn send(self: *WebSocketClient, text_or_binary: []const u8, is_binary: bool) !void {
        if (!self.connected) return error.NotConnected;

        var mask_key: [4]u8 = undefined;
        std.crypto.random.bytes(&mask_key);

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = if (is_binary) .Binary else .Text,
            .masked = true,
            .mask_key = mask_key,
            .payload = text_or_binary,
        };

        const bytes = try frame.serialize(self.allocator);
        defer self.allocator.free(bytes);

        if (self.is_tls) {
            _ = try self.tls_stream.?.write(bytes);
        } else {
            _ = std.c.write(self.sock_fd.?, bytes.ptr, bytes.len);
        }
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
