//! HTML5 Canvas 2D Rendering Context implementation.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const SoftwareRasterizer = @import("../graphics/software.zig").SoftwareRasterizer;

pub const CanvasRenderingContext2D = struct {
    rasterizer: *SoftwareRasterizer,
    fill_color: Color = Color.black,
    stroke_color: Color = Color.black,
    line_width: f32 = 1.0,

    pub fn init(rasterizer: *SoftwareRasterizer) CanvasRenderingContext2D {
        return .{
            .rasterizer = rasterizer,
            .fill_color = Color.black,
            .stroke_color = Color.black,
            .line_width = 1.0,
        };
    }

    pub fn fillRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        self.rasterizer.backend().drawRect(Rect.init(x, y, w, h), self.fill_color);
    }

    pub fn strokeRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        const edges = @import("../common/types.zig").BoxEdges.initAll(self.line_width);
        self.rasterizer.backend().drawBorder(Rect.init(x, y, w, h), edges, self.stroke_color);
    }

    pub fn clearRect(self: *CanvasRenderingContext2D, x: f32, y: f32, w: f32, h: f32) void {
        self.rasterizer.backend().drawRect(Rect.init(x, y, w, h), Color.transparent);
    }

    pub fn fillText(self: *CanvasRenderingContext2D, text: []const u8, x: f32, y: f32) void {
        self.rasterizer.backend().drawText(text, Point.init(x, y), 16.0, self.fill_color);
    }
};

test "canvas fillRect and strokeRect" {
    const allocator = std.testing.allocator;
    var raster = try SoftwareRasterizer.init(allocator, 100, 100);
    defer raster.deinit();

    var ctx = CanvasRenderingContext2D.init(&raster);
    ctx.fill_color = Color.blue;
    ctx.fillRect(10, 10, 50, 50);

    try std.testing.expectEqual(Color.blue.toU32(), raster.pixels[(20 * 100) + 20]);
}
