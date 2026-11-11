//! Layout tree construction from styled DOM nodes.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const StyleEngine = @import("../css/style.zig").StyleEngine;
const ComputedStyle = @import("../css/properties.zig").ComputedStyle;
const LayoutBox = @import("box.zig").LayoutBox;
const BoxType = @import("box.zig").BoxType;

pub fn buildLayoutTree(
    allocator: std.mem.Allocator,
    node: *const Node,
    style_engine: *StyleEngine,
    parent_style: ?*const ComputedStyle,
) !?*LayoutBox {
    if (node.node_type == .Text) {
        if (node.text_content) |txt| {
            const trimmed = std.mem.trim(u8, txt, " \t\r\n");
            if (trimmed.len == 0) return null;

            const style = if (parent_style) |p| p.* else ComputedStyle{};
            const box = try LayoutBox.create(allocator, .TextBox, node, style);
            box.text = try allocator.dupe(u8, trimmed);
            return box;
        }
        return null;
    }

    if (node.node_type != .Element and node.node_type != .Document) {
        return null;
    }

    const style = try style_engine.computeStyle(node, parent_style);
    if (style.display == .None) {
        return null;
    }

    const box_type: BoxType = switch (style.display) {
        .Flex => .FlexBox,
        .Grid => .GridBox,
        .Block => .BlockBox,
        .Inline, .InlineBlock => .InlineBox,
        .None => unreachable,
    };

    const root_box = try LayoutBox.create(allocator, box_type, node, style);

    var curr = node.first_child;
    while (curr) |child| {
        if (try buildLayoutTree(allocator, child, style_engine, &style)) |child_box| {
            try root_box.children.append(allocator, child_box);
        }
        curr = child.next_sibling;
    }

    return root_box;
}
