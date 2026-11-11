//! Box model dimensions and LayoutBox tree node definitions.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const BoxEdges = @import("../common/types.zig").BoxEdges;
const Node = @import("../dom/node.zig").Node;
const ComputedStyle = @import("../css/properties.zig").ComputedStyle;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const BoxType = enum {
    BlockBox,
    InlineBox,
    FlexBox,
    GridBox,
    AnonymousBlock,
    TextBox,
};

pub const Dimensions = struct {
    content: Rect = Rect.zero,
    padding: BoxEdges = BoxEdges.zero,
    border: BoxEdges = BoxEdges.zero,
    margin: BoxEdges = BoxEdges.zero,

    pub fn paddingBox(self: Dimensions) Rect {
        return .{
            .x = self.content.x - self.padding.left,
            .y = self.content.y - self.padding.top,
            .width = self.content.width + self.padding.horizontalTotal(),
            .height = self.content.height + self.padding.verticalTotal(),
        };
    }

    pub fn borderBox(self: Dimensions) Rect {
        const p_box = self.paddingBox();
        return .{
            .x = p_box.x - self.border.left,
            .y = p_box.y - self.border.top,
            .width = p_box.width + self.border.horizontalTotal(),
            .height = p_box.height + self.border.verticalTotal(),
        };
    }

    pub fn marginBox(self: Dimensions) Rect {
        const b_box = self.borderBox();
        return .{
            .x = b_box.x - self.margin.left,
            .y = b_box.y - self.margin.top,
            .width = b_box.width + self.margin.horizontalTotal(),
            .height = b_box.height + self.margin.verticalTotal(),
        };
    }
};

pub const LayoutBox = struct {
    box_type: BoxType,
    node: ?*const Node = null,
    style: ComputedStyle = .{},
    dimensions: Dimensions = .{},
    children: std.ArrayList(*LayoutBox),
    text: ?[]const u8 = null,
    dirty_layout: bool = true,
    dirty_paint: bool = true,

    pub fn create(allocator: std.mem.Allocator, box_type: BoxType, node: ?*const Node, style: ComputedStyle) !*LayoutBox {
        const box = try allocator.create(LayoutBox);
        box.* = .{
            .box_type = box_type,
            .node = node,
            .style = style,
            .dimensions = .{},
            .children = .empty,
            .text = null,
            .dirty_layout = true,
            .dirty_paint = true,
        };
        SubsystemMemoryTracker.global.recordAlloc(.Layout, @sizeOf(LayoutBox));
        return box;
    }

    pub fn deinit(self: *LayoutBox, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        if (self.text) |txt| {
            allocator.free(txt);
        }
        SubsystemMemoryTracker.global.recordFree(.Layout, @sizeOf(LayoutBox));
        allocator.destroy(self);
    }
};
