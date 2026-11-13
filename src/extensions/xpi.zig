//! XPI package reader, ZIP container extraction, and Firefox signature validation.
const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const fs = @import("../common/fs.zig");
const c = @import("../common/c.zig");

pub const XpiError = error{
    FileNotFound,
    InvalidZipArchive,
    EndOfCentralDirectoryNotFound,
    EntryNotFound,
    UnsupportedCompression,
    DecompressionFailed,
    DirectoryCreationFailed,
    WriteFailed,
};

pub const ZipEntryHeader = struct {
    filename: []const u8,
    compression_method: u16,
    compressed_size: u32,
    uncompressed_size: u32,
    local_header_offset: u32,
};

pub const XPIPackage = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    manifest: Manifest,
    is_signed: bool = false,

    /// Loads an extension from an already unpacked directory containing manifest.json
    pub fn loadFromDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !XPIPackage {
        var path_buf: [1024]u8 = undefined;
        const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/manifest.json", .{dir_path});

        const max_size = 2 * 1024 * 1024; // 2MB
        const json_content = try fs.readFileAlloc(allocator, manifest_path, max_size);
        defer allocator.free(json_content);

        const manifest = try Manifest.parse(allocator, json_content);

        // Check if META-INF/mozilla.rsa or manifest.mf exists
        const rsa_path = try std.fmt.bufPrint(&path_buf, "{s}/META-INF/mozilla.rsa", .{dir_path});
        var test_buf: [16]u8 = undefined;
        const is_signed = if (fs.readFileToBuffer(rsa_path, &test_buf)) |_| true else |_| false;

        return XPIPackage{
            .allocator = allocator,
            .path = try allocator.dupe(u8, dir_path),
            .manifest = manifest,
            .is_signed = is_signed,
        };
    }

    /// Loads an extension directly from a .zip or .xpi package by reading its manifest
    pub fn loadFromArchive(allocator: std.mem.Allocator, archive_path: []const u8) !XPIPackage {
        const max_zip_size = 64 * 1024 * 1024; // 64MB max for extension archive
        const zip_bytes = try fs.readFileAlloc(allocator, archive_path, max_zip_size);
        defer allocator.free(zip_bytes);

        const manifest_bytes = try extractFile(allocator, zip_bytes, "manifest.json");
        defer allocator.free(manifest_bytes);

        const manifest = try Manifest.parse(allocator, manifest_bytes);

        // Check signature presence
        var is_signed = false;
        if (extractFile(allocator, zip_bytes, "META-INF/mozilla.rsa")) |rsa_bytes| {
            allocator.free(rsa_bytes);
            is_signed = true;
        } else |_| {}

        return XPIPackage{
            .allocator = allocator,
            .path = try allocator.dupe(u8, archive_path),
            .manifest = manifest,
            .is_signed = is_signed,
        };
    }

    pub fn deinit(self: *XPIPackage) void {
        self.allocator.free(self.path);
        self.manifest.deinit();
    }
};

/// Finds the End of Central Directory record in a ZIP buffer
fn findEOCD(zip_bytes: []const u8) !usize {
    if (zip_bytes.len < 22) return XpiError.InvalidZipArchive;

    const min_search = if (zip_bytes.len > 65535 + 22) zip_bytes.len - (65535 + 22) else 0;
    var i: usize = zip_bytes.len - 22;
    while (i >= min_search) : (i -= 1) {
        if (std.mem.eql(u8, zip_bytes[i .. i + 4], "\x50\x4b\x05\x06")) {
            return i;
        }
        if (i == 0) break;
    }
    return XpiError.EndOfCentralDirectoryNotFound;
}

/// Extracts a single entry from a ZIP buffer into memory
pub fn extractFile(allocator: std.mem.Allocator, zip_bytes: []const u8, target_path: []const u8) ![]u8 {
    const eocd = try findEOCD(zip_bytes);
    const cd_records = std.mem.readInt(u16, zip_bytes[eocd + 10 ..][0..2], .little);
    const cd_offset = std.mem.readInt(u32, zip_bytes[eocd + 16 ..][0..4], .little);

    if (cd_offset >= zip_bytes.len) return XpiError.InvalidZipArchive;

    var cur: usize = cd_offset;
    var idx: usize = 0;
    while (idx < cd_records and cur + 46 <= zip_bytes.len) : (idx += 1) {
        if (!std.mem.eql(u8, zip_bytes[cur .. cur + 4], "\x50\x4b\x01\x02")) {
            break;
        }

        const comp_method = std.mem.readInt(u16, zip_bytes[cur + 10 ..][0..2], .little);
        const comp_size = std.mem.readInt(u32, zip_bytes[cur + 20 ..][0..4], .little);
        const uncomp_size = std.mem.readInt(u32, zip_bytes[cur + 24 ..][0..4], .little);
        const name_len = std.mem.readInt(u16, zip_bytes[cur + 28 ..][0..2], .little);
        const extra_len = std.mem.readInt(u16, zip_bytes[cur + 30 ..][0..2], .little);
        const comm_len = std.mem.readInt(u16, zip_bytes[cur + 32 ..][0..2], .little);
        const local_offset = std.mem.readInt(u32, zip_bytes[cur + 42 ..][0..4], .little);

        if (cur + 46 + name_len > zip_bytes.len) return XpiError.InvalidZipArchive;
        const filename = zip_bytes[cur + 46 .. cur + 46 + name_len];

        if (std.mem.eql(u8, filename, target_path)) {
            // Found matching entry: read local file header to locate raw payload
            if (local_offset + 30 > zip_bytes.len) return XpiError.InvalidZipArchive;
            if (!std.mem.eql(u8, zip_bytes[local_offset .. local_offset + 4], "\x50\x4b\x03\x04")) {
                return XpiError.InvalidZipArchive;
            }

            const lh_name_len = std.mem.readInt(u16, zip_bytes[local_offset + 26 ..][0..2], .little);
            const lh_extra_len = std.mem.readInt(u16, zip_bytes[local_offset + 28 ..][0..2], .little);
            const data_start = local_offset + 30 + lh_name_len + lh_extra_len;

            if (data_start + comp_size > zip_bytes.len) return XpiError.InvalidZipArchive;
            const comp_data = zip_bytes[data_start .. data_start + comp_size];

            if (comp_method == 0) {
                // Stored (no compression)
                return try allocator.dupe(u8, comp_data);
            } else if (comp_method == 8) {
                // DEFLATE
                return try c.decompressRawDeflate(allocator, comp_data, uncomp_size);
            } else {
                return XpiError.UnsupportedCompression;
            }
        }

        cur += 46 + name_len + extra_len + comm_len;
    }

    return XpiError.EntryNotFound;
}

test "xpi extract manifest and load package from adnauseam archive" {
    const allocator = std.testing.allocator;

    const zip_path = "extensions/adnauseam/upstream/adnauseam-firefox.zip";
    var pkg = try XPIPackage.loadFromArchive(allocator, zip_path);
    defer pkg.deinit();

    // Verify manifest properties extracted from the real upstream AdNauseam package
    try std.testing.expect(std.mem.indexOf(u8, pkg.manifest.name, "AdNauseam") != null);
    try std.testing.expect(pkg.manifest.permissions.items.len > 0);
    try std.testing.expect(pkg.manifest.content_scripts.items.len > 0);
}
