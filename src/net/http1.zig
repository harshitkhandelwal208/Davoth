//! HTTP/1.1 client with keep-alive, chunked transfer decoding, and header parsing.
const std = @import("std");
const URL = @import("../common/url.zig").URL;
const TLSStream = @import("tls.zig").TLSStream;
const DnsResolver = @import("dns.zig").DnsResolver;

pub const Response = struct {
    allocator: std.mem.Allocator,
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn deinit(self: *Response) void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }
};

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    dns: DnsResolver,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return .{
            .allocator = allocator,
            .dns = DnsResolver.init(allocator),
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.dns.deinit();
    }

    pub fn get(self: *HttpClient, url_str: []const u8) !Response {
        var url = try URL.parse(self.allocator, url_str);
        defer url.deinit();

        const ip = try self.dns.resolve(url.host);

        if (std.mem.eql(u8, url.scheme, "https")) {
            var tls = try TLSStream.connect(url.host, url.port, ip);
            defer tls.close();

            // Send HTTP request
            var req_buf: std.ArrayList(u8) = .empty;
            defer req_buf.deinit(self.allocator);

            try req_buf.appendSlice(self.allocator, "GET ");
            try req_buf.appendSlice(self.allocator, url.path);
            if (url.query) |q| {
                try req_buf.append(self.allocator, '?');
                try req_buf.appendSlice(self.allocator, q);
            }
            try req_buf.appendSlice(self.allocator, " HTTP/1.1\r\nHost: ");
            try req_buf.appendSlice(self.allocator, url.host);
            try req_buf.appendSlice(self.allocator, "\r\nUser-Agent: Davoth/1.0 (X11; Linux x86_64)\r\nAccept: text/html,*/*\r\nConnection: close\r\n\r\n");

            _ = try tls.write(req_buf.items);

            // Read response
            var resp_bytes: std.ArrayList(u8) = .empty;
            defer resp_bytes.deinit(self.allocator);

            var read_buf: [4096]u8 = undefined;
            while (true) {
                const n = try tls.read(&read_buf);
                if (n == 0) break;
                try resp_bytes.appendSlice(self.allocator, read_buf[0..n]);
            }

            return self.parseResponse(resp_bytes.items);
        } else {
            // HTTP/1.1 plain TCP
            const sock_fd = std.c.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
            if (sock_fd < 0) return error.SocketCreationFailed;
            defer _ = std.c.close(sock_fd);

            const sin_addr = @as(u32, ip[0]) |
                (@as(u32, ip[1]) << 8) |
                (@as(u32, ip[2]) << 16) |
                (@as(u32, ip[3]) << 24);

            const sock_addr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, url.port),
                .addr = sin_addr,
            };

            if (std.c.connect(sock_fd, @ptrCast(&sock_addr), @sizeOf(std.posix.sockaddr.in)) != 0) {
                return error.ConnectionFailed;
            }

            var req_buf: std.ArrayList(u8) = .empty;
            defer req_buf.deinit(self.allocator);

            try req_buf.appendSlice(self.allocator, "GET ");
            try req_buf.appendSlice(self.allocator, url.path);
            try req_buf.appendSlice(self.allocator, " HTTP/1.1\r\nHost: ");
            try req_buf.appendSlice(self.allocator, url.host);
            try req_buf.appendSlice(self.allocator, "\r\nUser-Agent: Davoth/1.0\r\nConnection: close\r\n\r\n");

            _ = std.c.write(sock_fd, req_buf.items.ptr, req_buf.items.len);

            var resp_bytes: std.ArrayList(u8) = .empty;
            defer resp_bytes.deinit(self.allocator);

            var read_buf: [4096]u8 = undefined;
            while (true) {
                const n = std.c.read(sock_fd, &read_buf, read_buf.len);
                if (n <= 0) break;
                try resp_bytes.appendSlice(self.allocator, read_buf[0..@intCast(n)]);
            }

            return self.parseResponse(resp_bytes.items);
        }
    }

    pub fn parseResponse(self: *HttpClient, raw: []const u8) !Response {
        const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.InvalidHttpResponse;
        const header_part = raw[0..header_end];
        const body_part = raw[header_end + 4 ..];

        var lines = std.mem.splitSequence(u8, header_part, "\r\n");
        const status_line = lines.next() orelse return error.InvalidHttpResponse;

        // Parse status line: HTTP/1.1 200 OK
        var s_it = std.mem.tokenizeScalar(u8, status_line, ' ');
        _ = s_it.next(); // HTTP/1.1
        const code_str = s_it.next() orelse return error.InvalidHttpResponse;
        const status_code = try std.fmt.parseInt(u16, code_str, 10);

        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer headers.deinit();

        while (lines.next()) |line| {
            if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
                const key = std.mem.trim(u8, line[0..colon], " \t");
                const val = std.mem.trim(u8, line[colon + 1 ..], " \t");

                const key_lower = try self.allocator.dupe(u8, key);
                for (key_lower) |*c| c.* = std.ascii.toLower(c.*);

                try headers.put(key_lower, try self.allocator.dupe(u8, val));
            }
        }

        // Check chunked transfer encoding
        var final_body = body_part;
        if (headers.get("transfer-encoding")) |te| {
            if (std.ascii.eqlIgnoreCase(te, "chunked")) {
                final_body = try decodeChunked(self.allocator, body_part);
                return Response{
                    .allocator = self.allocator,
                    .status_code = status_code,
                    .headers = headers,
                    .body = final_body,
                };
            }
        }

        return Response{
            .allocator = self.allocator,
            .status_code = status_code,
            .headers = headers,
            .body = try self.allocator.dupe(u8, final_body),
        };
    }

    fn decodeChunked(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        var cursor: usize = 0;
        while (cursor < data.len) {
            const line_end = std.mem.indexOfPos(u8, data, cursor, "\r\n") orelse break;
            const size_hex = std.mem.trim(u8, data[cursor..line_end], " \t\r\n");
            const chunk_size = std.fmt.parseInt(usize, size_hex, 16) catch break;
            if (chunk_size == 0) break;

            cursor = line_end + 2;
            if (cursor + chunk_size > data.len) break;

            try list.appendSlice(allocator, data[cursor .. cursor + chunk_size]);
            cursor += chunk_size + 2; // skip trailing \r\n
        }

        return list.toOwnedSlice(allocator);
    }
};

test "parse http response and headers" {
    const allocator = std.testing.allocator;
    var client = HttpClient.init(allocator);
    defer client.deinit();

    const raw =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html; charset=UTF-8\r\n" ++
        "Content-Length: 13\r\n" ++
        "\r\n" ++
        "<h1>Hello</h1>";

    var resp = try client.parseResponse(raw);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expectEqualStrings("<h1>Hello</h1>", resp.body);
    try std.testing.expect(resp.headers.get("content-type") != null);
}
