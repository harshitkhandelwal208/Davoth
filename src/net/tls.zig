//! TLS client connection using OpenSSL with ALPN and certificate validation.
const std = @import("std");
const posix = std.posix;
const c = @import("../common/c.zig");

pub const TLSStream = struct {
    ssl: ?*c.SSL,
    ctx: ?*c.SSL_CTX,
    sock_fd: c_int,
    alpn_selected: []const u8 = "",

    pub fn connect(host: []const u8, port: u16, ip: [4]u8) !TLSStream {
        // Initialize OpenSSL
        _ = c.OPENSSL_init_ssl(0, null);
        const method = c.TLS_client_method();
        const ctx = c.SSL_CTX_new(method) orelse return error.SslCtxInitFailed;
        errdefer c.SSL_CTX_free(ctx);

        // Configure default verify paths
        _ = c.SSL_CTX_set_default_verify_paths(ctx);

        // Configure ALPN: h2, http/1.1
        const alpn_protos = "\x02h2\x08http/1.1";
        _ = c.SSL_CTX_set_alpn_protos(ctx, alpn_protos, alpn_protos.len);

        const ssl = c.SSL_new(ctx) orelse return error.SslNewFailed;
        errdefer c.SSL_free(ssl);

        // SNI (Server Name Indication)
        var host_z: [256]u8 = undefined;
        if (host.len >= host_z.len) return error.HostTooLong;
        @memcpy(host_z[0..host.len], host);
        host_z[host.len] = 0;
        _ = c.SSL_set_tlsext_host_name(ssl, &host_z);

        // Connect TCP socket
        const sock_fd = std.c.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
        if (sock_fd < 0) return error.SocketCreationFailed;
        errdefer _ = std.c.close(sock_fd);

        const sin_addr = @as(u32, ip[0]) |
            (@as(u32, ip[1]) << 8) |
            (@as(u32, ip[2]) << 16) |
            (@as(u32, ip[3]) << 24);

        const sock_addr = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = std.mem.nativeToBig(u16, port),
            .addr = sin_addr,
        };

        if (std.c.connect(sock_fd, @ptrCast(&sock_addr), @sizeOf(posix.sockaddr.in)) != 0) {
            return error.ConnectionFailed;
        }

        _ = c.SSL_set_fd(ssl, sock_fd);

        const connect_rc = c.SSL_connect(ssl);
        if (connect_rc <= 0) {
            return error.TlsHandshakeFailed;
        }

        // Check ALPN result
        var proto_ptr: [*c]const u8 = null;
        var proto_len: c_uint = 0;
        c.SSL_get0_alpn_selected(ssl, &proto_ptr, &proto_len);

        var selected: []const u8 = "";
        if (proto_ptr != null and proto_len > 0) {
            selected = proto_ptr[0..proto_len];
        }

        return TLSStream{
            .ssl = ssl,
            .ctx = ctx,
            .sock_fd = sock_fd,
            .alpn_selected = selected,
        };
    }

    pub fn close(self: *TLSStream) void {
        if (self.ssl) |s| {
            _ = c.SSL_shutdown(s);
            c.SSL_free(s);
            self.ssl = null;
        }
        if (self.ctx) |cx| {
            c.SSL_CTX_free(cx);
            self.ctx = null;
        }
        _ = std.c.close(self.sock_fd);
    }

    pub fn write(self: *TLSStream, bytes: []const u8) !usize {
        const s = self.ssl orelse return error.NotConnected;
        const n = c.SSL_write(s, bytes.ptr, @intCast(bytes.len));
        if (n <= 0) return error.TlsWriteFailed;
        return @intCast(n);
    }

    pub fn read(self: *TLSStream, buf: []u8) !usize {
        const s = self.ssl orelse return error.NotConnected;
        const n = c.SSL_read(s, buf.ptr, @intCast(buf.len));
        if (n <= 0) return 0;
        return @intCast(n);
    }
};
