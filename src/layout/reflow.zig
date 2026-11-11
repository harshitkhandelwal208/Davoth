//! Incremental reflow and damage tracking.
const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const Dimensions = @import("box.zig").Dimensions;
const layoutBlock = @import("block.zig").layoutBlock;
const layoutFlex = @import("flex.zig").layoutFlex;

pub fn performLayout(root: *LayoutBox, viewport_w: f32, viewport_h: f32) void {
    var viewport_dim = Dimensions{};
    viewport_dim.content.width = viewport_w;
    viewport_dim.content.height = viewport_h;

    switch (root.style.display) {
        .Flex => layoutFlex(root, viewport_dim),
        else => layoutBlock(root, viewport_dim),
    }

    root.dirty_layout = false;
}

pub fn markDirty(box: *LayoutBox) void {
    box.dirty_layout = true;
    box.dirty_paint = true;
    for (box.children.items) |child| {
        markDirty(child);
    }
}
