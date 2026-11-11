//! CSS Selector parsing, specificity calculation, and DOM matching.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const Node = @import("../dom/node.zig").Node;

pub const Combinator = enum {
    None,
    Descendant, // ' '
    Child, // '>'
    AdjacentSibling, // '+'
    GeneralSibling, // '~'
};

pub const SimpleSelector = struct {
    tag_name: ?AtomId = null,
    id: ?[]const u8 = null,
    class_names: std.ArrayList([]const u8),
    attributes: std.ArrayList(struct { name: []const u8, value: ?[]const u8 }),
    pseudo_classes: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) SimpleSelector {
        _ = allocator;
        return .{
            .tag_name = null,
            .id = null,
            .class_names = .empty,
            .attributes = .empty,
            .pseudo_classes = .empty,
        };
    }

    pub fn deinit(self: *SimpleSelector, allocator: std.mem.Allocator) void {
        self.class_names.deinit(allocator);
        self.attributes.deinit(allocator);
        self.pseudo_classes.deinit(allocator);
    }
};

pub const ComplexSelectorPart = struct {
    selector: SimpleSelector,
    combinator: Combinator = .None,
};

pub const Selector = struct {
    allocator: std.mem.Allocator,
    parts: std.ArrayList(ComplexSelectorPart),

    pub fn init(allocator: std.mem.Allocator) Selector {
        return .{
            .allocator = allocator,
            .parts = .empty,
        };
    }

    pub fn deinit(self: *Selector) void {
        for (self.parts.items) |*part| {
            part.selector.deinit(self.allocator);
        }
        self.parts.deinit(self.allocator);
    }

    pub fn calculateSpecificity(self: *const Selector) u32 {
        var a: u32 = 0; // IDs
        var b: u32 = 0; // Classes, attributes, pseudo-classes
        var c: u32 = 0; // Type selectors

        for (self.parts.items) |part| {
            if (part.selector.id != null) a += 1;
            b += @intCast(part.selector.class_names.items.len);
            b += @intCast(part.selector.attributes.items.len);
            b += @intCast(part.selector.pseudo_classes.items.len);
            if (part.selector.tag_name != null and part.selector.tag_name.? != AtomId.empty) {
                c += 1;
            }
        }

        return (a * 10000) + (b * 100) + c;
    }

    pub fn matches(self: *const Selector, node: *const Node, table: *AtomTable) bool {
        if (node.node_type != .Element) return false;
        if (self.parts.items.len == 0) return false;

        var part_idx = self.parts.items.len - 1;
        var current_node: ?*const Node = node;

        // Check rightmost part first
        if (!matchesSimple(&self.parts.items[part_idx].selector, current_node.?, table)) {
            return false;
        }

        while (part_idx > 0) {
            const combinator = self.parts.items[part_idx - 1].combinator;
            part_idx -= 1;
            const prev_sel = &self.parts.items[part_idx].selector;

            switch (combinator) {
                .Child => {
                    current_node = current_node.?.parent_node;
                    if (current_node == null or !matchesSimple(prev_sel, current_node.?, table)) {
                        return false;
                    }
                },
                .Descendant => {
                    var found = false;
                    var ancestor = current_node.?.parent_node;
                    while (ancestor) |anc| {
                        if (anc.node_type == .Element and matchesSimple(prev_sel, anc, table)) {
                            current_node = anc;
                            found = true;
                            break;
                        }
                        ancestor = anc.parent_node;
                    }
                    if (!found) return false;
                },
                .AdjacentSibling => {
                    current_node = current_node.?.prev_sibling;
                    while (current_node != null and current_node.?.node_type != .Element) {
                        current_node = current_node.?.prev_sibling;
                    }
                    if (current_node == null or !matchesSimple(prev_sel, current_node.?, table)) {
                        return false;
                    }
                },
                else => return false,
            }
        }

        return true;
    }

    fn matchesSimple(sel: *const SimpleSelector, node: *const Node, table: *AtomTable) bool {
        if (node.node_type != .Element) return false;

        // Check tag name
        if (sel.tag_name) |tag| {
            if (tag != AtomId.empty and node.tag_name != tag) {
                return false;
            }
        }

        // Check ID
        if (sel.id) |id_str| {
            const id_atom = table.intern("id") catch return false;
            const elem_id = node.getAttribute(id_atom) orelse return false;
            if (!std.mem.eql(u8, elem_id, id_str)) return false;
        }

        // Check classes
        if (sel.class_names.items.len > 0) {
            const class_atom = table.intern("class") catch return false;
            const elem_classes = node.getAttribute(class_atom) orelse return false;

            for (sel.class_names.items) |required_class| {
                var found = false;
                var it = std.mem.tokenizeScalar(u8, elem_classes, ' ');
                while (it.next()) |cl| {
                    if (std.mem.eql(u8, cl, required_class)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
        }

        return true;
    }
};

test "css selector specificity and matching" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var sel = Selector.init(allocator);
    defer sel.deinit();

    var part = ComplexSelectorPart{
        .selector = SimpleSelector.init(allocator),
        .combinator = .None,
    };
    part.selector.tag_name = try table.intern("div");
    try part.selector.class_names.append(allocator, "card");
    try sel.parts.append(allocator, part);

    const spec = sel.calculateSpecificity();
    try std.testing.expectEqual(@as(u32, 101), spec); // 1 class (100) + 1 tag (1) = 101

    const node = try Node.create(allocator, .Element, try table.intern("div"));
    defer node.deinit(allocator);
    try node.setAttribute(allocator, try table.intern("class"), "card hero");

    try std.testing.expect(sel.matches(node, table));
}
