//! Standard Block & Inline formatting context layout algorithms.
const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const Dimensions = @import("box.zig").Dimensions;
const layoutFlex = @import("flex.zig").layoutFlex;
const layoutGrid = @import("grid.zig").layoutGrid;
const FontMetrics = @import("text.zig").FontMetrics;
const breakLines = @import("text.zig").breakLines;

pub fn layoutBlock(box: *LayoutBox, containing_block: Dimensions) void {
    // 1. Calculate width
    calculateBlockWidth(box, containing_block);

    // 2. Position box relative to containing block
    calculateBlockPosition(box, containing_block);

    // 3. Layout children
    layoutBlockChildren(box);

    // 4. Calculate height
    calculateBlockHeight(box, containing_block);
}

fn calculateBlockWidth(box: *LayoutBox, containing_block: Dimensions) void {
    const avail_w = containing_block.content.width;

    box.dimensions.padding = box.style.padding.resolve(avail_w, containing_block.content.height);
    box.dimensions.border = box.style.border_widths;
    box.dimensions.margin = box.style.margin.resolve(avail_w, containing_block.content.height);

    const non_content_w = box.dimensions.padding.horizontalTotal() +
        box.dimensions.border.horizontalTotal() +
        box.dimensions.margin.horizontalTotal();

    if (box.style.width.unit != .Auto) {
        box.dimensions.content.width = box.style.width.resolve(avail_w);
    } else {
        box.dimensions.content.width = @max(0.0, avail_w - non_content_w);
    }
}

fn calculateBlockPosition(box: *LayoutBox, containing_block: Dimensions) void {
    box.dimensions.content.x = containing_block.content.x +
        box.dimensions.margin.left +
        box.dimensions.border.left +
        box.dimensions.padding.left;

    box.dimensions.content.y = containing_block.content.y +
        box.dimensions.margin.top +
        box.dimensions.border.top +
        box.dimensions.padding.top;
}

fn layoutBlockChildren(box: *LayoutBox) void {
    var cur_y = box.dimensions.content.y;

    for (box.children.items) |child| {
        child.dimensions.content.x = box.dimensions.content.x;
        child.dimensions.content.y = cur_y;

        switch (child.style.display) {
            .Flex => layoutFlex(child, box.dimensions),
            .Grid => layoutGrid(child, box.dimensions),
            .Block => layoutBlock(child, box.dimensions),
            .Inline, .InlineBlock => {
                // Inline layout
                const metrics = FontMetrics.default(child.style.font_size);
                if (child.text) |txt| {
                    child.dimensions.content.width = metrics.measureText(txt);
                    child.dimensions.content.height = metrics.line_height;
                } else {
                    child.dimensions.content.width = 50.0;
                    child.dimensions.content.height = metrics.line_height;
                }
            },
            .None => {},
        }

        const child_total_h = child.dimensions.marginBox().height;
        cur_y += child_total_h;
    }
}

fn calculateBlockHeight(box: *LayoutBox, containing_block: Dimensions) void {
    if (box.style.height.unit != .Auto) {
        box.dimensions.content.height = box.style.height.resolve(containing_block.content.height);
    } else {
        var total_h: f32 = 0.0;
        for (box.children.items) |child| {
            total_h += child.dimensions.marginBox().height;
        }
        if (box.text) |txt| {
            _ = txt;
            total_h = @max(total_h, box.style.font_size * box.style.line_height);
        }
        box.dimensions.content.height = total_h;
    }
}
