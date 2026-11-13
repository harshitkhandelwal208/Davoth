//! Retained Display List items and tree-to-display-list generator.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;
const Point = @import("../common/types.zig").Point;
const Color = @import("../common/types.zig").Color;
const BoxEdges = @import("../common/types.zig").BoxEdges;
const LayoutBox = @import("../layout/box.zig").LayoutBox;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const DisplayItem = union(enum) {
    DrawRect: struct {
        rect: Rect,
        color: Color,
    },
    DrawBorder: struct {
        rect: Rect,
        widths: BoxEdges,
        color: Color,
    },
    DrawText: struct {
        text: []const u8,
        origin: Point,
        font_size: f32,
        color: Color,
    },
    PushClip: Rect,
    PopClip: void,
};

pub const DisplayList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(DisplayItem),

    pub fn init(allocator: std.mem.Allocator) DisplayList {
        return .{
            .allocator = allocator,
            .items = .empty,
        };
    }

    pub fn deinit(self: *DisplayList) void {
        SubsystemMemoryTracker.global.recordFree(.RenderDisplayList, self.items.items.len * @sizeOf(DisplayItem));
        self.items.deinit(self.allocator);
    }

    pub fn build(self: *DisplayList, root: *const LayoutBox) !void {
        try self.renderBox(root);
        SubsystemMemoryTracker.global.recordAlloc(.RenderDisplayList, self.items.items.len * @sizeOf(DisplayItem));
    }

    fn renderBox(self: *DisplayList, box: *const LayoutBox) !void {
        const opacity_factor = @max(0.0, @min(1.0, box.style.opacity));

        // 1. Draw background
        if (box.style.background_color.a > 0 and opacity_factor > 0.0) {
            var bg_col = box.style.background_color;
            if (opacity_factor < 1.0) {
                bg_col.a = @intFromFloat(@as(f32, @floatFromInt(bg_col.a)) * opacity_factor);
            }
            try self.items.append(self.allocator, .{
                .DrawRect = .{
                    .rect = box.dimensions.borderBox(),
                    .color = bg_col,
                },
            });
        }

        // 2. Draw border
        if (box.dimensions.border.horizontalTotal() > 0 or box.dimensions.border.verticalTotal() > 0) {
            var border_col = box.style.border_color;
            if (opacity_factor < 1.0) {
                border_col.a = @intFromFloat(@as(f32, @floatFromInt(border_col.a)) * opacity_factor);
            }
            try self.items.append(self.allocator, .{
                .DrawBorder = .{
                    .rect = box.dimensions.borderBox(),
                    .widths = box.dimensions.border,
                    .color = border_col,
                },
            });
        }

        // 3. Draw text content
        if (box.text) |txt| {
            var text_col = box.style.color;
            if (opacity_factor < 1.0) {
                text_col.a = @intFromFloat(@as(f32, @floatFromInt(text_col.a)) * opacity_factor);
            }
            try self.items.append(self.allocator, .{
                .DrawText = .{
                    .text = txt,
                    .origin = Point.init(box.dimensions.content.x, box.dimensions.content.y + (box.style.font_size * 0.8)),
                    .font_size = box.style.font_size,
                    .color = text_col,
                },
            });
        }

        // 4. Render children
        for (box.children.items) |child| {
            try self.renderBox(child);
        }
    }
};

test "display list build from layout box" {
    const allocator = std.testing.allocator;
    const box = try LayoutBox.create(allocator, .BlockBox, null, .{
        .background_color = Color.blue,
    });
    defer box.deinit(allocator);

    box.dimensions.content = Rect.init(0, 0, 200, 100);

    var dlist = DisplayList.init(allocator);
    defer dlist.deinit();

    try dlist.build(box);
    try std.testing.expect(dlist.items.items.len > 0);
    try std.testing.expectEqual(Color.blue.toU32(), dlist.items.items[0].DrawRect.color.toU32());
}
