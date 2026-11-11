//! Common interface for graphics backends (Software and Vulkan).
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const BoxEdges = @import("../common/types.zig").BoxEdges;

pub const GraphicsBackendType = enum {
    Software,
    Vulkan,
};

pub const GraphicsBackend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        clear: *const fn (ctx: *anyopaque, color: Color) void,
        drawRect: *const fn (ctx: *anyopaque, rect: Rect, color: Color) void,
        drawBorder: *const fn (ctx: *anyopaque, rect: Rect, widths: BoxEdges, color: Color) void,
        drawText: *const fn (ctx: *anyopaque, text: []const u8, origin: Point, size: f32, color: Color) void,
        present: *const fn (ctx: *anyopaque) void,
    };

    pub fn clear(self: GraphicsBackend, color: Color) void {
        self.vtable.clear(self.ptr, color);
    }

    pub fn drawRect(self: GraphicsBackend, rect: Rect, color: Color) void {
        self.vtable.drawRect(self.ptr, rect, color);
    }

    pub fn drawBorder(self: GraphicsBackend, rect: Rect, widths: BoxEdges, color: Color) void {
        self.vtable.drawBorder(self.ptr, rect, widths, color);
    }

    pub fn drawText(self: GraphicsBackend, text: []const u8, origin: Point, size: f32, color: Color) void {
        self.vtable.drawText(self.ptr, text, origin, size, color);
    }

    pub fn present(self: GraphicsBackend) void {
        self.vtable.present(self.ptr);
    }
};
