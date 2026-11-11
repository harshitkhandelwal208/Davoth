//! CSS Grid layout algorithm.
const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const Dimensions = @import("box.zig").Dimensions;

pub fn layoutGrid(box: *LayoutBox, containing_block: Dimensions) void {
    const container_w = if (box.style.width.unit != .Auto)
        box.style.width.resolve(containing_block.content.width)
    else
        containing_block.content.width;

    box.dimensions.content.width = container_w;
    box.dimensions.padding = box.style.padding.resolve(container_w, containing_block.content.height);
    box.dimensions.border = box.style.border_widths;
    box.dimensions.margin = box.style.margin.resolve(container_w, containing_block.content.height);

    // Default 2-column grid layout if unspecified
    const columns: usize = 2;
    const col_width = container_w / @as(f32, @floatFromInt(columns));
    const row_height: f32 = 60.0;

    var cur_col: usize = 0;
    var cur_row: usize = 0;

    for (box.children.items) |child| {
        child.dimensions.content.x = box.dimensions.content.x + (@as(f32, @floatFromInt(cur_col)) * col_width);
        child.dimensions.content.y = box.dimensions.content.y + (@as(f32, @floatFromInt(cur_row)) * row_height);
        child.dimensions.content.width = col_width;
        child.dimensions.content.height = row_height;

        cur_col += 1;
        if (cur_col >= columns) {
            cur_col = 0;
            cur_row += 1;
        }
    }

    if (box.style.height.unit != .Auto) {
        box.dimensions.content.height = box.style.height.resolve(containing_block.content.height);
    } else {
        const total_rows = if (cur_col > 0) cur_row + 1 else cur_row;
        box.dimensions.content.height = @as(f32, @floatFromInt(total_rows)) * row_height;
    }
}
