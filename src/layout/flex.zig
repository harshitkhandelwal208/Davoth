//! Flexbox layout algorithm.
const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const Dimensions = @import("box.zig").Dimensions;

pub fn layoutFlex(box: *LayoutBox, containing_block: Dimensions) void {
    const is_row = (box.style.flex_direction == .Row or box.style.flex_direction == .RowReverse);

    // Resolve width and height
    const container_w = if (box.style.width.unit != .Auto)
        box.style.width.resolve(containing_block.content.width)
    else
        containing_block.content.width;

    box.dimensions.content.width = container_w;
    box.dimensions.padding = box.style.padding.resolve(container_w, containing_block.content.height);
    box.dimensions.border = box.style.border_widths;
    box.dimensions.margin = box.style.margin.resolve(container_w, containing_block.content.height);

    const inner_w = box.dimensions.content.width;
    var total_main_size: f32 = 0.0;
    var max_cross_size: f32 = 0.0;
    var total_grow: f32 = 0.0;

    // 1. Measure children
    for (box.children.items) |child| {
        const item_w = if (child.style.width.unit != .Auto) child.style.width.resolve(inner_w) else 100.0;
        const item_h = if (child.style.height.unit != .Auto) child.style.height.resolve(inner_w) else 40.0;

        child.dimensions.content.width = item_w;
        child.dimensions.content.height = item_h;

        if (is_row) {
            total_main_size += item_w;
            max_cross_size = @max(max_cross_size, item_h);
        } else {
            total_main_size += item_h;
            max_cross_size = @max(max_cross_size, item_w);
        }
        total_grow += child.style.flex_grow;
    }

    const available_space = inner_w - total_main_size;

    // 2. Distribute flex-grow if positive space
    if (available_space > 0.0 and total_grow > 0.0) {
        for (box.children.items) |child| {
            if (child.style.flex_grow > 0.0) {
                const extra = (child.style.flex_grow / total_grow) * available_space;
                if (is_row) {
                    child.dimensions.content.width += extra;
                } else {
                    child.dimensions.content.height += extra;
                }
            }
        }
    }

    // 3. Position items along main axis & cross axis
    var current_main: f32 = box.dimensions.content.x;
    const current_cross: f32 = box.dimensions.content.y;

    var gap: f32 = 0.0;
    if (box.children.items.len > 1 and available_space > 0.0 and total_grow == 0.0) {
        switch (box.style.justify_content) {
            .Center => current_main += available_space / 2.0,
            .FlexEnd => current_main += available_space,
            .SpaceBetween => gap = available_space / @as(f32, @floatFromInt(box.children.items.len - 1)),
            else => {},
        }
    }

    for (box.children.items) |child| {
        if (is_row) {
            child.dimensions.content.x = current_main;
            child.dimensions.content.y = current_cross;
            current_main += child.dimensions.content.width + gap;
        } else {
            child.dimensions.content.x = current_cross;
            child.dimensions.content.y = current_main;
            current_main += child.dimensions.content.height + gap;
        }
    }

    if (box.style.height.unit != .Auto) {
        box.dimensions.content.height = box.style.height.resolve(containing_block.content.height);
    } else {
        box.dimensions.content.height = if (is_row) max_cross_size else (current_main - box.dimensions.content.y);
    }
}
