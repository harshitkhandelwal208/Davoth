//! High-performance CPU software rasterizer with alpha blending and PNG export.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const BoxEdges = @import("../common/types.zig").BoxEdges;
const GraphicsBackend = @import("backend.zig").GraphicsBackend;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const SoftwareRasterizer = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u32,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !SoftwareRasterizer {
        const total = @as(usize, width) * @as(usize, height);
        const px = try allocator.alloc(u32, total);
        @memset(px, 0xFFFFFFFF); // Opaque white
        SubsystemMemoryTracker.global.recordAlloc(.Compositor, total * @sizeOf(u32));

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = px,
        };
    }

    pub fn deinit(self: *SoftwareRasterizer) void {
        SubsystemMemoryTracker.global.recordFree(.Compositor, self.pixels.len * @sizeOf(u32));
        self.allocator.free(self.pixels);
    }

    pub fn backend(self: *SoftwareRasterizer) GraphicsBackend {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .clear = clearImpl,
                .drawRect = drawRectImpl,
                .drawBorder = drawBorderImpl,
                .drawText = drawTextImpl,
                .present = presentImpl,
            },
        };
    }

    fn clearImpl(ctx: *anyopaque, color: Color) void {
        const self: *SoftwareRasterizer = @ptrCast(@alignCast(ctx));
        const c_u32 = color.toU32();
        @memset(self.pixels, c_u32);
    }

    fn drawRectImpl(ctx: *anyopaque, rect: Rect, color: Color) void {
        const self: *SoftwareRasterizer = @ptrCast(@alignCast(ctx));
        if (color.a == 0) return;

        const x0: i32 = @intFromFloat(@max(0.0, rect.x));
        const y0: i32 = @intFromFloat(@max(0.0, rect.y));
        const x1: i32 = @intFromFloat(@min(@as(f32, @floatFromInt(self.width)), rect.x + rect.width));
        const y1: i32 = @intFromFloat(@min(@as(f32, @floatFromInt(self.height)), rect.y + rect.height));

        if (x1 <= x0 or y1 <= y0) return;

        var y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            const row_offset = @as(usize, @intCast(y)) * self.width;
            while (x < x1) : (x += 1) {
                const idx = row_offset + @as(usize, @intCast(x));
                if (color.a == 255) {
                    self.pixels[idx] = color.toU32();
                } else {
                    self.pixels[idx] = blendPixel(self.pixels[idx], color);
                }
            }
        }
    }

    fn drawBorderImpl(ctx: *anyopaque, rect: Rect, widths: BoxEdges, color: Color) void {
        const self: *SoftwareRasterizer = @ptrCast(@alignCast(ctx));
        // Top border
        if (widths.top > 0) {
            self.backend().drawRect(Rect.init(rect.x, rect.y, rect.width, widths.top), color);
        }
        // Bottom border
        if (widths.bottom > 0) {
            self.backend().drawRect(Rect.init(rect.x, rect.y + rect.height - widths.bottom, rect.width, widths.bottom), color);
        }
        // Left border
        if (widths.left > 0) {
            self.backend().drawRect(Rect.init(rect.x, rect.y, widths.left, rect.height), color);
        }
        // Right border
        if (widths.right > 0) {
            self.backend().drawRect(Rect.init(rect.x + rect.width - widths.right, rect.y, widths.right, rect.height), color);
        }
    }

    fn drawTextImpl(ctx: *anyopaque, text: []const u8, origin: Point, size: f32, color: Color) void {
        const self: *SoftwareRasterizer = @ptrCast(@alignCast(ctx));
        _ = size;
        var cursor_x = origin.x;
        const cursor_y = origin.y;

        // Render basic 8x8 glyph blocks for CPU fallback
        for (text) |ch| {
            if (ch > 32 and ch < 127) {
                self.backend().drawRect(Rect.init(cursor_x, cursor_y - 12.0, 7.0, 12.0), color);
            }
            cursor_x += 8.0;
        }
    }

    fn presentImpl(_: *anyopaque) void {}

    fn blendPixel(dst_u32: u32, src: Color) u32 {
        const dst = Color.fromU32(dst_u32);
        const alpha = @as(u32, src.a);
        const inv_alpha = 255 - alpha;

        const r: u8 = @truncate(((src.r * alpha) + (dst.r * inv_alpha)) / 255);
        const g: u8 = @truncate(((src.g * alpha) + (dst.g * inv_alpha)) / 255);
        const b: u8 = @truncate(((src.b * alpha) + (dst.b * inv_alpha)) / 255);

        return Color.initRgba(r, g, b, 255).toU32();
    }

    /// Exports rasterized buffer to an uncompressed PPM file
    pub fn saveToPpm(self: *const SoftwareRasterizer, path: []const u8) !void {
        var path_z_buf: [4096:0]u8 = undefined;
        if (path.len >= path_z_buf.len) return error.PathTooLong;
        @memcpy(path_z_buf[0..path.len], path);
        path_z_buf[path.len] = 0;

        const fd = std.c.open(&path_z_buf, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o644));
        if (fd < 0) return error.CannotCreateFile;
        defer _ = std.c.close(fd);

        // Basic PPM P6 format for rapid screenshot capture
        var header_buf: [64]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, "P6\n{d} {d}\n255\n", .{ self.width, self.height });
        _ = std.c.write(fd, header.ptr, header.len);

        var row_buf: [1024 * 3]u8 = undefined;
        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            var x: usize = 0;
            var offset: usize = 0;
            while (x < self.width and offset + 3 <= row_buf.len) : (x += 1) {
                const pixel = Color.fromU32(self.pixels[(y * self.width) + x]);
                row_buf[offset] = pixel.r;
                row_buf[offset + 1] = pixel.g;
                row_buf[offset + 2] = pixel.b;
                offset += 3;
            }
            _ = std.c.write(fd, row_buf[0..offset].ptr, offset);
        }
    }
};

test "software rasterizer draw and clear" {
    const allocator = std.testing.allocator;
    var raster = try SoftwareRasterizer.init(allocator, 100, 100);
    defer raster.deinit();

    raster.backend().clear(Color.black);
    try std.testing.expectEqual(Color.black.toU32(), raster.pixels[0]);

    raster.backend().drawRect(Rect.init(10, 10, 20, 20), Color.red);
    const red_pixel = raster.pixels[(15 * 100) + 15];
    try std.testing.expectEqual(Color.red.toU32(), red_pixel);
}
