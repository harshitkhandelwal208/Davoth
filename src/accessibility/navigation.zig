//! Keyboard focus navigation and spatial focus ring tracking.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;

pub const FocusManager = struct {
    focused_node: ?*Node = null,

    pub fn focus(self: *FocusManager, node: *Node) void {
        self.focused_node = node;
    }

    pub fn blur(self: *FocusManager) void {
        self.focused_node = null;
    }
};
