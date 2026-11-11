//! Accessibility tree, ARIA roles, and states.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;

pub const AccessibleRole = enum {
    Document,
    Heading,
    Button,
    Link,
    TextBox,
    CheckBox,
    RadioButton,
    StaticText,
    GenericContainer,
};

pub const AccessibleState = packed struct(u8) {
    focusable: bool = false,
    focused: bool = false,
    disabled: bool = false,
    checked: bool = false,
    expanded: bool = false,
    _pad: u3 = 0,
};

pub const AccessibleNode = struct {
    role: AccessibleRole,
    name: []const u8,
    state: AccessibleState = .{},
    children: std.ArrayList(*AccessibleNode),

    pub fn create(allocator: std.mem.Allocator, role: AccessibleRole, name: []const u8) !*AccessibleNode {
        const node = try allocator.create(AccessibleNode);
        node.* = .{
            .role = role,
            .name = try allocator.dupe(u8, name),
            .state = .{},
            .children = .empty,
        };
        return node;
    }

    pub fn deinit(self: *AccessibleNode, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self);
    }
};

test "accessible node creation" {
    const allocator = std.testing.allocator;
    const btn = try AccessibleNode.create(allocator, .Button, "Submit Form");
    defer btn.deinit(allocator);

    try std.testing.expectEqual(AccessibleRole.Button, btn.role);
    try std.testing.expectEqualStrings("Submit Form", btn.name);
}
