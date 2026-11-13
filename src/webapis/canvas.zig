//! HTML5 Canvas 2D Rendering Context implementation.
//! Provides path construction, state save/restore, 2D affine transforms,
//! pixel-level ImageData read/write, text rendering, and primitives.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const SoftwareRasterizer = @import("../graphics/software.zig").SoftwareRasterizer;

pub const ImageData = struct {
    width: u32,
    height: u32,
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !ImageData {
        const total = @as(usize, width) * @as(usize, height) * 4;
        const buf = try allocator.alloc(u8, total);
        @memset(buf, 0);
        return .{
            .width = width,
            .height = height,
            .data = buf,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImageData) void {
        self.allocator.free(self.data);
    }
};

pub const CanvasState = struct {
    fill_color: Color,
    stroke_color: Color,
    line_width: f32,
    transform_x: f32,
    transform_y: f32,
    scale_x: f32,
    scale_y: f32,
};

pub const PathCommand = union(enum) {
    MoveTo: Point,
    LineTo: Point,
    Rect: Rect,
    Close: void,
};

pub const CanvasRenderingContext2D = struct {
    allocator: std.mem.Allocator,
    rasterizer: *SoftwareRasterizer,
    fill_color: Color = Color.black,
    stroke_color: Color = Color.black,
    line_width: f32 = 1.0,

    transform_x: f32 = 0.0,
    transform_y: f32 = 0.0,
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,

    path: std.ArrayList(PathCommand),
    state_stack: std.ArrayList(CanvasState),

    pub fn init(allocator: std.mem.Allocator, rasterizer: *SoftwareRasterizer) CanvasRenderingContext2D {
        return .{
            .allocator = allocator,
            .rasterizer = rasterizer,
            .fill_color = Color.black,
            .stroke_color = Color.black,
            .line_width = 1.0,
            .transform_x = 0.0,
            .transform_y = 0.0,
            .scale_x = 1.0,
            .scale_y = 1.0,
            .path = .empty,
            .state_stack = .empty,
        };
    }

    pub fn deinit(self: *CanvasRenderingContext2D) void {
        self.path.deinit(self.allocator);
        self.state_stack.deinit(self.allocator);
    }

    pub fn fillRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        const rx = (x * self.scale_x) + self.transform_x;
        const ry = (y * self.scale_y) + self.transform_y;
        const rw = w * self.scale_x;
        const rh = h * self.scale_y;
        self.rasterizer.backend().drawRect(Rect.init(rx, ry, rw, rh), self.fill_color);
    }

    pub fn strokeRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        const rx = (x * self.scale_x) + self.transform_x;
        const ry = (y * self.scale_y) + self.transform_y;
        const rw = w * self.scale_x;
        const rh = h * self.scale_y;
        const edges = @import("../common/types.zig").BoxEdges.initAll(self.line_width * self.scale_x);
        self.rasterizer.backend().drawBorder(Rect.init(rx, ry, rw, rh), edges, self.stroke_color);
    }

    pub fn clearRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        const rx = (x * self.scale_x) + self.transform_x;
        const ry = (y * self.scale_y) + self.transform_y;
        const rw = w * self.scale_x;
        const rh = h * self.scale_y;
        self.rasterizer.backend().drawRect(Rect.init(rx, ry, rw, rh), Color.transparent);
    }

    pub fn fillText(self: *CanvasRenderingContext2D, text: []const u8, x: f32, y: f32) void {
        const rx = (x * self.scale_x) + self.transform_x;
        const ry = (y * self.scale_y) + self.transform_y;
        self.rasterizer.backend().drawText(text, Point.init(rx, ry), 16.0 * self.scale_x, self.fill_color);
    }

    pub fn strokeText(self: *CanvasRenderingContext2D, text: []const u8, x: f32, y: f32) void {
        const rx = (x * self.scale_x) + self.transform_x;
        const ry = (y * self.scale_y) + self.transform_y;
        self.rasterizer.backend().drawText(text, Point.init(rx, ry), 16.0 * self.scale_x, self.stroke_color);
    }

    pub fn measureText(_: *CanvasRenderingContext2D, text: []const u8) f32 {
        return @as(f32, @floatFromInt(text.len)) * 9.6;
    }

    // Path methods
    pub fn beginPath(self: *CanvasRenderingContext2D) void {
        self.path.clearRetainingCapacity();
    }

    pub fn closePath(self: *CanvasRenderingContext2D) !void {
        try self.path.append(self.allocator, .Close);
    }

    pub fn moveTo(self: *CanvasRenderingContext2D, x: f32, y: f32) !void {
        try self.path.append(self.allocator, .{ .MoveTo = Point.init(x, y) });
    }

    pub fn lineTo(self: *CanvasRenderingContext2D, x: f32, y: f32) !void {
        try self.path.append(self.allocator, .{ .LineTo = Point.init(x, y) });
    }

    pub fn rect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) !void {
        try self.path.append(self.allocator, .{ .Rect = Rect.init(x, y, w, h) });
    }

    pub fn stroke(self: *CanvasRenderingContext2D) void {
        for (self.path.items) |cmd| {
            switch (cmd) {
                .Rect => |r| {
                    self.strokeRect(r.x, r.y, r.width, r.height);
                },
                .LineTo => |pt| {
                    const rx = (pt.x * self.scale_x) + self.transform_x;
                    const ry = (pt.y * self.scale_y) + self.transform_y;
                    self.rasterizer.backend().drawRect(Rect.init(rx, ry, self.line_width, self.line_width), self.stroke_color);
                },
                else => {},
            }
        }
    }

    pub fn fill(self: *CanvasRenderingContext2D) void {
        for (self.path.items) |cmd| {
            switch (cmd) {
                .Rect => |r| {
                    self.fillRect(r.x, r.y, r.width, r.height);
                },
                else => {},
            }
        }
    }

    // State management
    pub fn save(self: *CanvasRenderingContext2D) !void {
        try self.state_stack.append(self.allocator, .{
            .fill_color = self.fill_color,
            .stroke_color = self.stroke_color,
            .line_width = self.line_width,
            .transform_x = self.transform_x,
            .transform_y = self.transform_y,
            .scale_x = self.scale_x,
            .scale_y = self.scale_y,
        });
    }

    pub fn restore(self: *CanvasRenderingContext2D) void {
        if (self.state_stack.items.len > 0) {
            const state = self.state_stack.pop().?;
            self.fill_color = state.fill_color;
            self.stroke_color = state.stroke_color;
            self.line_width = state.line_width;
            self.transform_x = state.transform_x;
            self.transform_y = state.transform_y;
            self.scale_x = state.scale_x;
            self.scale_y = state.scale_y;
        }
    }

    // Affine transforms
    pub fn translate(self: *CanvasRenderingContext2D, tx: f32, ty: f32) void {
        self.transform_x += tx * self.scale_x;
        self.transform_y += ty * self.scale_y;
    }

    pub fn scale(self: *CanvasRenderingContext2D, sx: f32, sy: f32) void {
        self.scale_x *= sx;
        self.scale_y *= sy;
    }

    pub fn resetTransform(self: *CanvasRenderingContext2D) void {
        self.transform_x = 0.0;
        self.transform_y = 0.0;
        self.scale_x = 1.0;
        self.scale_y = 1.0;
    }

    // ImageData pixel manipulation
    pub fn createImageData(self: *CanvasRenderingContext2D, width: u32, height: u32) !ImageData {
        return ImageData.init(self.allocator, width, height);
    }

    pub fn getImageData(self: *CanvasRenderingContext2D, sx: i32, sy: i32, sw: u32, sh: u32) !ImageData {
        var img = try ImageData.init(self.allocator, sw, sh);
        errdefer img.deinit();

        const canvas_w = @as(i32, @intCast(self.rasterizer.width));
        const canvas_h = @as(i32, @intCast(self.rasterizer.height));

        var y: u32 = 0;
        while (y < sh) : (y += 1) {
            const py = sy + @as(i32, @intCast(y));
            if (py < 0 or py >= canvas_h) continue;

            var x: u32 = 0;
            while (x < sw) : (x += 1) {
                const px = sx + @as(i32, @intCast(x));
                if (px < 0 or px >= canvas_w) continue;

                const pixel_idx = @as(usize, @intCast(py)) * self.rasterizer.width + @as(usize, @intCast(px));
                const c_val = Color.fromU32(self.rasterizer.pixels[pixel_idx]);
                const dest_idx = (@as(usize, y) * sw + @as(usize, x)) * 4;

                img.data[dest_idx + 0] = c_val.r;
                img.data[dest_idx + 1] = c_val.g;
                img.data[dest_idx + 2] = c_val.b;
                img.data[dest_idx + 3] = c_val.a;
            }
        }
        return img;
    }

    pub fn putImageData(self: *CanvasRenderingContext2D, img: *const ImageData, dx: i32, dy: i32) void {
        const canvas_w = @as(i32, @intCast(self.rasterizer.width));
        const canvas_h = @as(i32, @intCast(self.rasterizer.height));

        var y: u32 = 0;
        while (y < img.height) : (y += 1) {
            const py = dy + @as(i32, @intCast(y));
            if (py < 0 or py >= canvas_h) continue;

            var x: u32 = 0;
            while (x < img.width) : (x += 1) {
                const px = dx + @as(i32, @intCast(x));
                if (px < 0 or px >= canvas_w) continue;

                const src_idx = (@as(usize, y) * img.width + @as(usize, x)) * 4;
                const r = img.data[src_idx + 0];
                const g = img.data[src_idx + 1];
                const b = img.data[src_idx + 2];
                const a = img.data[src_idx + 3];

                const col = Color.initRgba(r, g, b, a);
                const pixel_idx = @as(usize, @intCast(py)) * self.rasterizer.width + @as(usize, @intCast(px));
                self.rasterizer.pixels[pixel_idx] = col.toU32();
            }
        }
    }
};

test "canvas fillRect, strokeRect, paths, transforms and imageData" {
    const allocator = std.testing.allocator;
    var raster = try SoftwareRasterizer.init(allocator, 100, 100);
    defer raster.deinit();

    var ctx = CanvasRenderingContext2D.init(allocator, &raster);
    defer ctx.deinit();

    ctx.fill_color = Color.blue;
    ctx.fillRect(10, 10, 50, 50);

    try std.testing.expectEqual(Color.blue.toU32(), raster.pixels[(20 * 100) + 20]);

    // Test save / restore and transforms
    try ctx.save();
    ctx.translate(10, 10);
    ctx.scale(2.0, 2.0);
    ctx.fill_color = Color.red;
    ctx.fillRect(0, 0, 10, 10); // translated to (10, 10) scaled to 20x20
    try std.testing.expectEqual(Color.red.toU32(), raster.pixels[(15 * 100) + 15]);

    ctx.restore();
    try std.testing.expectEqual(Color.blue.toU32(), ctx.fill_color.toU32());
    try std.testing.expectEqual(@as(f32, 1.0), ctx.scale_x);

    // Test getImageData and putImageData
    var img_data = try ctx.getImageData(10, 10, 20, 20);
    defer img_data.deinit();
    try std.testing.expectEqual(@as(u8, 255), img_data.data[0]); // Red R channel at (10,10)
    try std.testing.expectEqual(@as(u8, 255), img_data.data[3]); // Alpha

    // Put image data at (70, 70)
    ctx.putImageData(&img_data, 70, 70);
    try std.testing.expectEqual(Color.red.toU32(), raster.pixels[(75 * 100) + 75]);
}
