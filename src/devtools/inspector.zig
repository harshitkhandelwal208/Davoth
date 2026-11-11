//! Developer Tools: DOM inspector and CSS live style inspector.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const StyleEngine = @import("../css/style.zig").StyleEngine;
const ComputedStyle = @import("../css/properties.zig").ComputedStyle;

pub const DomInspector = struct {
    pub fn dumpNodeTree(node: *const Node, depth: usize) void {
        var indent_buf: [128]u8 = undefined;
        const indent_len = @min(depth * 2, indent_buf.len);
        @memset(indent_buf[0..indent_len], ' ');
        const indent = indent_buf[0..indent_len];

        switch (node.node_type) {
            .Element => {
                std.debug.print("{s}<Element tag={d} attrs={d}>\n", .{ indent, node.tag_name.toU32(), node.attributes.items.len });
            },
            .Text => {
                std.debug.print("{s}\"Text: {s}\"\n", .{ indent, node.text_content orelse "" });
            },
            .Document => {
                std.debug.print("{s}#document\n", .{indent});
            },
            else => {
                std.debug.print("{s}#node\n", .{indent});
            },
        }

        var curr = node.first_child;
        while (curr) |child| {
            dumpNodeTree(child, depth + 1);
            curr = child.next_sibling;
        }
    }
};
