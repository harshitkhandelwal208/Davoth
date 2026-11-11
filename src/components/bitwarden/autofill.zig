//! Form detection and credential autofill injection for Bitwarden.
const std = @import("std");
const Node = @import("../../dom/node.zig").Node;
const AtomTable = @import("../../common/string.zig").AtomTable;
const Vault = @import("vault.zig").Vault;
const LoginData = @import("vault.zig").LoginData;

pub const FormField = struct {
    username_node: ?*Node = null,
    password_node: ?*Node = null,
};

pub fn detectLoginForm(node: *Node, table: *AtomTable) FormField {
    var field = FormField{};
    findFieldsRecursive(node, table, &field);
    return field;
}

fn findFieldsRecursive(node: *Node, table: *AtomTable, field: *FormField) void {
    if (node.node_type == .Element) {
        const input_atom = table.intern("input") catch return;
        const type_atom = table.intern("type") catch return;

        if (node.tag_name == input_atom) {
            const t_val = node.getAttribute(type_atom) orelse "text";
            if (std.ascii.eqlIgnoreCase(t_val, "password")) {
                field.password_node = node;
            } else if (std.ascii.eqlIgnoreCase(t_val, "text") or std.ascii.eqlIgnoreCase(t_val, "email")) {
                if (field.username_node == null) {
                    field.username_node = node;
                }
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        findFieldsRecursive(child, table, field);
        curr = child.next_sibling;
    }
}

pub fn autofillForm(allocator: std.mem.Allocator, form: FormField, creds: LoginData, table: *AtomTable) !void {
    const val_atom = try table.intern("value");
    if (form.username_node) |u_node| {
        try u_node.setAttribute(allocator, val_atom, creds.username);
    }
    if (form.password_node) |p_node| {
        try p_node.setAttribute(allocator, val_atom, creds.password);
    }
}

test "form detection and credential autofill" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const form = try Node.create(allocator, .Element, try table.intern("form"));
    defer form.deinit(allocator);

    const u_input = try Node.create(allocator, .Element, try table.intern("input"));
    try u_input.setAttribute(allocator, try table.intern("type"), "email");
    try form.appendChild(allocator, u_input);

    const p_input = try Node.create(allocator, .Element, try table.intern("input"));
    try p_input.setAttribute(allocator, try table.intern("type"), "password");
    try form.appendChild(allocator, p_input);

    const detected = detectLoginForm(form, table);
    try std.testing.expect(detected.username_node != null);
    try std.testing.expect(detected.password_node != null);

    try autofillForm(allocator, detected, .{
        .uri = "",
        .username = "alice@example.com",
        .password = "Secr3t!",
    }, table);

    try std.testing.expectEqualStrings("alice@example.com", u_input.getAttribute(try table.intern("value")).?);
    try std.testing.expectEqualStrings("Secr3t!", p_input.getAttribute(try table.intern("value")).?);
}
