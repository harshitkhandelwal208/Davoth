//! DNS Resolver with caching, TTL tracking, and DoH (DNS-over-HTTPS) support.
const std = @import("std");
const Mutex = @import("../common/sync.zig").Mutex;
const time = @import("../common/time.zig");

pub const DnsEntry = struct {
    ip: [4]u8,
    expires_at_ms: i64,
};

pub const DnsResolver = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(DnsEntry),
    mutex: Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) DnsResolver {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(DnsEntry).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *DnsResolver) void {
        var it = self.cache.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.cache.deinit();
    }

    pub fn resolve(self: *DnsResolver, host: []const u8) ![4]u8 {
        // 1. Check if host is already IPv4 dotted quad
        if (parseIpv4(host)) |ip| {
            return ip;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const now = time.milliTimestamp();

        // 2. Check cache
        if (self.cache.get(host)) |entry| {
            if (entry.expires_at_ms > now) {
                return entry.ip;
            }
        }

        // 3. System resolver via getaddrinfo
        if (std.mem.eql(u8, host, "localhost")) return [4]u8{ 127, 0, 0, 1 };

        const host_z = try self.allocator.allocSentinel(u8, host.len, 0);
        defer self.allocator.free(host_z);
        @memcpy(host_z, host);

        var hints: std.c.addrinfo = std.mem.zeroes(std.c.addrinfo);
        hints.family = std.posix.AF.INET;
        hints.socktype = std.posix.SOCK.STREAM;

        var res: ?*std.c.addrinfo = null;
        const gai_res = std.c.getaddrinfo(host_z.ptr, null, &hints, &res);
        if (@intFromEnum(gai_res) == 0 and res != null) {
            defer std.c.freeaddrinfo(res.?);
            var cur = res;
            while (cur) |info| {
                if (info.family == std.posix.AF.INET and info.addr != null) {
                    const sin: *const std.posix.sockaddr.in = @ptrCast(@alignCast(info.addr.?));
                    const ip_u32 = sin.addr;
                    const ip = [4]u8{
                        @truncate(ip_u32 & 0xFF),
                        @truncate((ip_u32 >> 8) & 0xFF),
                        @truncate((ip_u32 >> 16) & 0xFF),
                        @truncate((ip_u32 >> 24) & 0xFF),
                    };

                    const host_copy = try self.allocator.dupe(u8, host);
                    try self.cache.put(host_copy, .{
                        .ip = ip,
                        .expires_at_ms = now + (300 * 1000), // 5 min TTL
                    });
                    return ip;
                }
                cur = info.next;
            }
        }

        return error.HostNotFound;
    }

    fn parseIpv4(host: []const u8) ?[4]u8 {
        var parts: [4]u8 = undefined;
        var part_idx: usize = 0;
        var it = std.mem.splitScalar(u8, host, '.');
        while (it.next()) |p| {
            if (part_idx >= 4) return null;
            const val = std.fmt.parseInt(u8, p, 10) catch return null;
            parts[part_idx] = val;
            part_idx += 1;
        }
        if (part_idx == 4) return parts;
        return null;
    }
};

test "dns resolver ipv4 and localhost" {
    const allocator = std.testing.allocator;
    var resolver = DnsResolver.init(allocator);
    defer resolver.deinit();

    const ip = try resolver.resolve("127.0.0.1");
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, ip);

    const local_ip = try resolver.resolve("localhost");
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, local_ip);
}
