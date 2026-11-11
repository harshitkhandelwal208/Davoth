//! Hit testing mapping screen coordinates to layout boxes.
const std = @import("std");
const Point = @import("../common/types.zig").Point;
const LayoutBox = @import("box.zig").LayoutBox;

pub fn hitTest(box: *const LayoutBox, pt: Point) ?*const LayoutBox {
    // Check if point is inside this box's borderBox
    if (!box.dimensions.borderBox().contains(pt)) {
        return null;
    }

    // Check children in reverse order (topmost child first)
    var i = box.children.items.len;
    while (i > 0) {
        i -= 1;
        const child = box.children.items[i];
        if (hitTest(child, pt)) |hit| {
            return hit;
        }
    }

    return box;
}

test "hit test coordinate detection" {
    const allocator = std.testing.allocator;
    const box = try LayoutBox.create(allocator, .BlockBox, null, .{});
    defer box.deinit(allocator);

    box.dimensions.content.x = 20;
    box.dimensions.content.y = 20;
    box.dimensions.content.width = 100;
    box.dimensions.content.height = 100;

    const hit = hitTest(box, Point.init(50, 50));
    try std.testing.expect(hit == box);

    const miss = hitTest(box, Point.init(150, 150));
    try std.testing.expect(miss == null);
}
