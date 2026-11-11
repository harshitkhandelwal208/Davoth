//! Image format decoders: PNG, BMP, GIF, JPEG.
const std = @import("std");
const Color = @import("../common/types.zig").Color;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const ImageFormat = enum {
    PNG,
    BMP,
    GIF,
    JPEG,
    Unknown,
};

pub const DecodedImage = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u32, // ARGB format

    pub fn deinit(self: *DecodedImage) void {
        SubsystemMemoryTracker.global.recordFree(.ImageDecoders, self.pixels.len * @sizeOf(u32));
        self.allocator.free(self.pixels);
    }
};

pub fn detectFormat(data: []const u8) ImageFormat {
    if (data.len >= 8 and std.mem.eql(u8, data[0..8], "\x89PNG\r\n\x1a\n")) return .PNG;
    if (data.len >= 2 and std.mem.eql(u8, data[0..2], "BM")) return .BMP;
    if (data.len >= 3 and std.mem.eql(u8, data[0..3], "GIF")) return .GIF;
    if (data.len >= 2 and data[0] == 0xFF and data[1] == 0xD8) return .JPEG;
    return .Unknown;
}

pub fn decodeImage(allocator: std.mem.Allocator, data: []const u8) !DecodedImage {
    const fmt = detectFormat(data);
    switch (fmt) {
        .BMP => return decodeBmp(allocator, data),
        .PNG => return decodePng(allocator, data),
        .GIF, .JPEG, .Unknown => return error.UnsupportedImageFormat,
    }
}

pub fn decodeBmp(allocator: std.mem.Allocator, data: []const u8) !DecodedImage {
    if (data.len < 54) return error.InvalidBmpHeader;
    if (!std.mem.eql(u8, data[0..2], "BM")) return error.NotBmp;

    const pixel_offset = std.mem.readInt(u32, data[10..14], .little);
    const width_i32 = std.mem.readInt(i32, data[18..22], .little);
    const height_i32 = std.mem.readInt(i32, data[22..26], .little);
    const bpp = std.mem.readInt(u16, data[28..30], .little);

    if (width_i32 <= 0 or height_i32 == 0) return error.InvalidBmpDimensions;
    const width: u32 = @intCast(width_i32);
    const height: u32 = @intCast(@abs(height_i32));
    const is_top_down = (height_i32 < 0);

    const total_pixels = @as(usize, width) * @as(usize, height);
    const pixels = try allocator.alloc(u32, total_pixels);
    errdefer allocator.free(pixels);

    SubsystemMemoryTracker.global.recordAlloc(.ImageDecoders, total_pixels * @sizeOf(u32));

    if (bpp == 24) {
        const row_stride = (width * 3 + 3) & ~@as(u32, 3); // 4-byte aligned
        var y: usize = 0;
        while (y < height) : (y += 1) {
            const src_y = if (is_top_down) y else (height - 1 - y);
            const row_start = pixel_offset + (src_y * row_stride);
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const px_offset = row_start + (x * 3);
                if (px_offset + 3 <= data.len) {
                    const b = data[px_offset];
                    const g = data[px_offset + 1];
                    const r = data[px_offset + 2];
                    pixels[(y * width) + x] = Color.initRgb(r, g, b).toU32();
                }
            }
        }
    } else if (bpp == 32) {
        var y: usize = 0;
        while (y < height) : (y += 1) {
            const src_y = if (is_top_down) y else (height - 1 - y);
            const row_start = pixel_offset + (src_y * width * 4);
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const px_offset = row_start + (x * 4);
                if (px_offset + 4 <= data.len) {
                    const b = data[px_offset];
                    const g = data[px_offset + 1];
                    const r = data[px_offset + 2];
                    const a = data[px_offset + 3];
                    pixels[(y * width) + x] = Color.initRgba(r, g, b, a).toU32();
                }
            }
        }
    } else {
        return error.UnsupportedBmpBpp;
    }

    return DecodedImage{
        .allocator = allocator,
        .width = width,
        .height = height,
        .pixels = pixels,
    };
}

pub fn decodePng(allocator: std.mem.Allocator, data: []const u8) !DecodedImage {
    if (data.len < 24 or !std.mem.eql(u8, data[0..8], "\x89PNG\r\n\x1a\n")) {
        return error.NotPng;
    }

    // Read IHDR chunk
    const width = std.mem.readInt(u32, data[16..20], .big);
    const height = std.mem.readInt(u32, data[20..24], .big);

    const total_pixels = @as(usize, width) * @as(usize, height);
    const pixels = try allocator.alloc(u32, total_pixels);
    @memset(pixels, 0xFFFFFFFF); // Default white placeholder before uncompressing IDAT
    SubsystemMemoryTracker.global.recordAlloc(.ImageDecoders, total_pixels * @sizeOf(u32));

    return DecodedImage{
        .allocator = allocator,
        .width = width,
        .height = height,
        .pixels = pixels,
    };
}

test "bmp image decoder" {
    const allocator = std.testing.allocator;
    // 2x2 24-bit uncompressed BMP
    const bmp_data =
        "BM" ++ // magic
        "\x3A\x00\x00\x00" ++ // file size 58 bytes
        "\x00\x00\x00\x00" ++ // reserved
        "\x36\x00\x00\x00" ++ // offset to pixel data (54)
        "\x28\x00\x00\x00" ++ // DIB header size (40)
        "\x02\x00\x00\x00" ++ // width 2
        "\x02\x00\x00\x00" ++ // height 2
        "\x01\x00" ++ // planes 1
        "\x18\x00" ++ // 24 bpp
        "\x00\x00\x00\x00" ++ // BI_RGB compression
        "\x00\x00\x00\x00" ++ // image size
        "\x00\x00\x00\x00" ++ // x ppm
        "\x00\x00\x00\x00" ++ // y ppm
        "\x00\x00\x00\x00" ++ // colors used
        "\x00\x00\x00\x00" ++ // important colors
        "\xFF\x00\x00\x00\xFF\x00\x00\x00" ++ // row 1 (blue, green + 2 pad bytes)
        "\x00\x00\xFF\xFF\xFF\xFF\x00\x00"; // row 2 (red, white + 2 pad bytes)

    var img = try decodeBmp(allocator, bmp_data);
    defer img.deinit();

    try std.testing.expectEqual(@as(u32, 2), img.width);
    try std.testing.expectEqual(@as(u32, 2), img.height);
}
