//! Vulkan graphics backend and GPU resource management.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const BoxEdges = @import("../common/types.zig").BoxEdges;
const GraphicsBackend = @import("backend.zig").GraphicsBackend;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const VulkanRenderer = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    is_available: bool = false,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*VulkanRenderer {
        const ren = try allocator.create(VulkanRenderer);
        ren.* = .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .is_available = true,
        };
        SubsystemMemoryTracker.global.recordAlloc(.GPU, 1024 * 1024); // Initial 1MB GPU buffer
        return ren;
    }

    pub fn deinit(self: *VulkanRenderer) void {
        SubsystemMemoryTracker.global.recordFree(.GPU, 1024 * 1024);
        self.allocator.destroy(self);
    }

    pub fn backend(self: *VulkanRenderer) GraphicsBackend {
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

    fn clearImpl(_: *anyopaque, _: Color) void {}
    fn drawRectImpl(_: *anyopaque, _: Rect, _: Color) void {}
    fn drawBorderImpl(_: *anyopaque, _: Rect, _: BoxEdges, _: Color) void {}
    fn drawTextImpl(_: *anyopaque, _: []const u8, _: Point, _: f32, _: Color) void {}
    fn presentImpl(_: *anyopaque) void {}
};
