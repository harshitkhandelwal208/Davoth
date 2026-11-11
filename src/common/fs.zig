//! File system utilities using libc and POSIX for Davoth.
const std = @import("std");
const c = std.c;

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const path_z = try allocator.allocSentinel(u8, path.len, 0);
    defer allocator.free(path_z);
    @memcpy(path_z, path);

    const fd = c.open(path_z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.FileNotFound;
    defer _ = c.close(fd);

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (list.items.len < max_bytes) {
        const to_read = @min(chunk.len, max_bytes - list.items.len);
        const n = c.read(fd, &chunk, to_read);
        if (n <= 0) break;
        try list.appendSlice(allocator, chunk[0..@intCast(n)]);
    }

    return list.toOwnedSlice(allocator);
}

pub fn readFileToBuffer(path: []const u8, buf: []u8) !usize {
    var path_z_buf: [4096:0]u8 = undefined;
    if (path.len >= path_z_buf.len) return error.PathTooLong;
    @memcpy(path_z_buf[0..path.len], path);
    path_z_buf[path.len] = 0;

    const fd = c.open(&path_z_buf, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.FileNotFound;
    defer _ = c.close(fd);

    const n = c.read(fd, buf.ptr, buf.len);
    if (n < 0) return error.ReadFailed;
    return @intCast(n);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    var path_z_buf: [4096:0]u8 = undefined;
    if (path.len >= path_z_buf.len) return error.PathTooLong;
    @memcpy(path_z_buf[0..path.len], path);
    path_z_buf[path.len] = 0;

    const fd = c.open(&path_z_buf, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o644));
    if (fd < 0) return error.CannotCreateFile;
    defer _ = c.close(fd);

    var written: usize = 0;
    while (written < data.len) {
        const n = c.write(fd, data[written..].ptr, data[written..].len);
        if (n <= 0) return error.WriteFailed;
        written += @intCast(n);
    }
}

test "fs utilities" {
    const data = try readFileAlloc(std.testing.allocator, "/etc/hostname", 1024);
    defer std.testing.allocator.free(data);
    try std.testing.expect(data.len > 0);
}
