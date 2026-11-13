//! Intelligent DOM Form Detection and Credential Autofill Engine for Bitwarden.
const std = @import("std");
const Node = @import("../../dom/node.zig").Node;
const AtomTable = @import("../../common/string.zig").AtomTable;
const Vault = @import("vault.zig").Vault;
const LoginData = @import("vault.zig").LoginData;
const CardData = @import("vault.zig").CardData;
const IdentityData = @import("vault.zig").IdentityData;

pub const LoginForm = struct {
    username_node: ?*Node = null,
    password_node: ?*Node = null,
    totp_node: ?*Node = null,
    submit_node: ?*Node = null,
};

pub const FormField = LoginForm; // Backward compatibility alias

pub const CardForm = struct {
    name_node: ?*Node = null,
    number_node: ?*Node = null,
    exp_month_node: ?*Node = null,
    exp_year_node: ?*Node = null,
    code_node: ?*Node = null,
};

pub const IdentityForm = struct {
    first_name_node: ?*Node = null,
    last_name_node: ?*Node = null,
    email_node: ?*Node = null,
    phone_node: ?*Node = null,
    address_node: ?*Node = null,
    city_node: ?*Node = null,
    state_node: ?*Node = null,
    postal_code_node: ?*Node = null,
    country_node: ?*Node = null,
};

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// Intelligent form detection heuristic identifying username, password, and TOTP inputs
pub fn detectLoginForm(node: *Node, table: *AtomTable) LoginForm {
    var form = LoginForm{};
    var candidate_input: ?*Node = null;
    scanLoginFieldsRecursive(node, table, &form, &candidate_input);
    if (form.username_node == null and form.password_node != null) {
        form.username_node = candidate_input;
    }
    return form;
}

fn scanLoginFieldsRecursive(node: *Node, table: *AtomTable, form: *LoginForm, candidate_input: *?*Node) void {
    if (node.node_type == .Element) {
        const input_atom = table.intern("input") catch return;
        const button_atom = table.intern("button") catch return;
        const type_atom = table.intern("type") catch return;
        const name_atom = table.intern("name") catch return;
        const id_atom = table.intern("id") catch return;
        const auto_atom = table.intern("autocomplete") catch return;
        const place_atom = table.intern("placeholder") catch return;

        if (node.tag_name == input_atom) {
            const t_val = node.getAttribute(type_atom) orelse "text";
            const auto_val = node.getAttribute(auto_atom) orelse "";
            const name_val = node.getAttribute(name_atom) orelse "";
            const id_val = node.getAttribute(id_atom) orelse "";
            const place_val = node.getAttribute(place_atom) orelse "";

            if (std.ascii.eqlIgnoreCase(t_val, "password") or
                containsIgnoreCase(auto_val, "password"))
            {
                if (form.password_node == null) {
                    form.password_node = node;
                }
            } else if (containsIgnoreCase(auto_val, "one-time-code") or
                containsIgnoreCase(name_val, "totp") or
                containsIgnoreCase(name_val, "otp") or
                containsIgnoreCase(id_val, "totp"))
            {
                if (form.totp_node == null) {
                    form.totp_node = node;
                }
            } else if (std.ascii.eqlIgnoreCase(t_val, "text") or
                std.ascii.eqlIgnoreCase(t_val, "email") or
                containsIgnoreCase(auto_val, "username") or
                containsIgnoreCase(auto_val, "email"))
            {
                candidate_input.* = node;
                if (form.username_node == null) {
                    const is_login_field = std.ascii.eqlIgnoreCase(t_val, "email") or
                        containsIgnoreCase(name_val, "user") or
                        containsIgnoreCase(name_val, "login") or
                        containsIgnoreCase(name_val, "email") or
                        containsIgnoreCase(id_val, "user") or
                        containsIgnoreCase(id_val, "login") or
                        containsIgnoreCase(id_val, "email") or
                        containsIgnoreCase(place_val, "email") or
                        containsIgnoreCase(place_val, "username") or
                        form.password_node != null;

                    if (is_login_field) {
                        form.username_node = node;
                    }
                }
            } else if (std.ascii.eqlIgnoreCase(t_val, "submit")) {
                if (form.submit_node == null) form.submit_node = node;
            }
        } else if (node.tag_name == button_atom) {
            const t_val = node.getAttribute(type_atom) orelse "submit";
            if (std.ascii.eqlIgnoreCase(t_val, "submit") and form.submit_node == null) {
                form.submit_node = node;
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        scanLoginFieldsRecursive(child, table, form, candidate_input);
        curr = child.next_sibling;
    }
}

/// Detects credit card payment input fields
pub fn detectCardForm(node: *Node, table: *AtomTable) CardForm {
    var form = CardForm{};
    scanCardFieldsRecursive(node, table, &form);
    return form;
}

fn scanCardFieldsRecursive(node: *Node, table: *AtomTable, form: *CardForm) void {
    if (node.node_type == .Element) {
        const input_atom = table.intern("input") catch return;
        const auto_atom = table.intern("autocomplete") catch return;
        const name_atom = table.intern("name") catch return;
        const id_atom = table.intern("id") catch return;

        if (node.tag_name == input_atom) {
            const auto_val = node.getAttribute(auto_atom) orelse "";
            const name_val = node.getAttribute(name_atom) orelse "";
            const id_val = node.getAttribute(id_atom) orelse "";

            if (std.mem.indexOf(u8, auto_val, "cc-number") != null or
                std.mem.indexOf(u8, name_val, "cardnumber") != null or
                std.mem.indexOf(u8, id_val, "card-number") != null)
            {
                form.number_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "cc-name") != null or
                std.mem.indexOf(u8, name_val, "cardholder") != null)
            {
                form.name_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "cc-exp-month") != null or
                std.mem.indexOf(u8, name_val, "exp-month") != null)
            {
                form.exp_month_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "cc-exp-year") != null or
                std.mem.indexOf(u8, name_val, "exp-year") != null)
            {
                form.exp_year_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "cc-csc") != null or
                std.mem.indexOf(u8, name_val, "cvv") != null or
                std.mem.indexOf(u8, name_val, "cvc") != null)
            {
                form.code_node = node;
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        scanCardFieldsRecursive(child, table, form);
        curr = child.next_sibling;
    }
}

/// Detects address, identity and contact fields
pub fn detectIdentityForm(node: *Node, table: *AtomTable) IdentityForm {
    var form = IdentityForm{};
    scanIdentityFieldsRecursive(node, table, &form);
    return form;
}

fn scanIdentityFieldsRecursive(node: *Node, table: *AtomTable, form: *IdentityForm) void {
    if (node.node_type == .Element) {
        const input_atom = table.intern("input") catch return;
        const auto_atom = table.intern("autocomplete") catch return;
        const name_atom = table.intern("name") catch return;

        if (node.tag_name == input_atom) {
            const auto_val = node.getAttribute(auto_atom) orelse "";
            const name_val = node.getAttribute(name_atom) orelse "";

            if (std.mem.indexOf(u8, auto_val, "given-name") != null or std.mem.indexOf(u8, name_val, "first_name") != null) {
                form.first_name_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "family-name") != null or std.mem.indexOf(u8, name_val, "last_name") != null) {
                form.last_name_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "email") != null or std.mem.indexOf(u8, name_val, "email") != null) {
                form.email_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "tel") != null or std.mem.indexOf(u8, name_val, "phone") != null) {
                form.phone_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "address-line1") != null or std.mem.indexOf(u8, name_val, "address") != null) {
                form.address_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "address-level2") != null or std.mem.indexOf(u8, name_val, "city") != null) {
                form.city_node = node;
            } else if (std.mem.indexOf(u8, auto_val, "postal-code") != null or std.mem.indexOf(u8, name_val, "zip") != null) {
                form.postal_code_node = node;
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        scanIdentityFieldsRecursive(child, table, form);
        curr = child.next_sibling;
    }
}

pub fn autofillForm(allocator: std.mem.Allocator, form: LoginForm, creds: LoginData, table: *AtomTable) !void {
    try autofillLoginForm(allocator, form, creds, table);
}

pub fn autofillLoginForm(allocator: std.mem.Allocator, form: LoginForm, creds: LoginData, table: *AtomTable) !void {
    const val_atom = try table.intern("value");
    if (form.username_node) |u_node| {
        try u_node.setAttribute(allocator, val_atom, creds.username);
    }
    if (form.password_node) |p_node| {
        try p_node.setAttribute(allocator, val_atom, creds.password);
    }
    if (form.totp_node) |t_node| {
        if (creds.totp) |t| {
            try t_node.setAttribute(allocator, val_atom, t);
        }
    }
}

pub fn autofillCardForm(allocator: std.mem.Allocator, form: CardForm, card: CardData, table: *AtomTable) !void {
    const val_atom = try table.intern("value");
    if (form.name_node) |n_node| {
        try n_node.setAttribute(allocator, val_atom, card.cardholder_name);
    }
    if (form.number_node) |num_node| {
        try num_node.setAttribute(allocator, val_atom, card.number);
    }
    if (form.exp_month_node) |em_node| {
        try em_node.setAttribute(allocator, val_atom, card.exp_month);
    }
    if (form.exp_year_node) |ey_node| {
        try ey_node.setAttribute(allocator, val_atom, card.exp_year);
    }
    if (form.code_node) |c_node| {
        try c_node.setAttribute(allocator, val_atom, card.code);
    }
}

pub fn autofillIdentityForm(allocator: std.mem.Allocator, form: IdentityForm, id: IdentityData, table: *AtomTable) !void {
    const val_atom = try table.intern("value");
    if (form.first_name_node) |fn_node| {
        try fn_node.setAttribute(allocator, val_atom, id.first_name);
    }
    if (form.last_name_node) |ln_node| {
        try ln_node.setAttribute(allocator, val_atom, id.last_name);
    }
    if (form.email_node) |e_node| {
        try e_node.setAttribute(allocator, val_atom, id.email);
    }
    if (form.phone_node) |p_node| {
        try p_node.setAttribute(allocator, val_atom, id.phone);
    }
    if (form.address_node) |a_node| {
        try a_node.setAttribute(allocator, val_atom, id.address1);
    }
    if (form.city_node) |c_node| {
        try c_node.setAttribute(allocator, val_atom, id.city);
    }
    if (form.postal_code_node) |pc_node| {
        try pc_node.setAttribute(allocator, val_atom, id.postal_code);
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

test "credit card form detection and autofill" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const form = try Node.create(allocator, .Element, try table.intern("form"));
    defer form.deinit(allocator);

    const num_input = try Node.create(allocator, .Element, try table.intern("input"));
    try num_input.setAttribute(allocator, try table.intern("autocomplete"), "cc-number");
    try form.appendChild(allocator, num_input);

    const cvc_input = try Node.create(allocator, .Element, try table.intern("input"));
    try cvc_input.setAttribute(allocator, try table.intern("autocomplete"), "cc-csc");
    try form.appendChild(allocator, cvc_input);

    const detected = detectCardForm(form, table);
    try std.testing.expect(detected.number_node != null);
    try std.testing.expect(detected.code_node != null);

    try autofillCardForm(allocator, detected, .{
        .cardholder_name = "Alice Smith",
        .brand = "Visa",
        .number = "4111222233334444",
        .exp_month = "12",
        .exp_year = "2028",
        .code = "123",
    }, table);

    try std.testing.expectEqualStrings("4111222233334444", num_input.getAttribute(try table.intern("value")).?);
    try std.testing.expectEqualStrings("123", cvc_input.getAttribute(try table.intern("value")).?);
}
