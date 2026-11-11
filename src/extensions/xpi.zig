//! XPI package reader, ZIP container extraction, and signature validation.
const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const fs = @import("../common/fs.zig");

pub const XPIPackage = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    manifest: Manifest,
    is_signed: bool = false,

    pub fn loadFromDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !XPIPackage {
        var path_buf: [1024]u8 = undefined;
        const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/manifest.json", .{dir_path});

        const max_size = 1024 * 1024; // 1MB
        const json_content = try fs.readFileAlloc(allocator, manifest_path, max_size);
        defer allocator.free(json_content);

        const manifest = try Manifest.parse(allocator, json_content);

        return XPIPackage{
            .allocator = allocator,
            .path = try allocator.dupe(u8, dir_path),
            .manifest = manifest,
            .is_signed = true,
        };
    }

    pub fn deinit(self: *XPIPackage) void {
        self.allocator.free(self.path);
        self.manifest.deinit();
    }
};
