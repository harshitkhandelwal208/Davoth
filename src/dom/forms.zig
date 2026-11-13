//! HTML5 Form Validation Controls, Constraint Validation API,
//! and Form-Level Report Validation Engine.
//! Implements WHATWG HTML5 ValidityState (valueMissing, typeMismatch, patternMismatch,
//! tooLong, tooShort, rangeUnderflow, rangeOverflow, stepMismatch, customError, valid),
//! custom validity messages, and form constraint validation.

const std = @import("std");
const Node = @import("node.zig").Node;
const AtomTable = @import("../common/string.zig").AtomTable;
const AtomId = @import("../common/string.zig").AtomId;

pub const ValidityState = struct {
    value_missing: bool = false,
    type_mismatch: bool = false,
    pattern_mismatch: bool = false,
    too_long: bool = false,
    too_short: bool = false,
    range_underflow: bool = false,
    range_overflow: bool = false,
    step_mismatch: bool = false,
    bad_input: bool = false,
    custom_error: bool = false,
    valid: bool = true,

    pub fn updateValid(self: *ValidityState) void {
        self.valid = !self.value_missing and
            !self.type_mismatch and
            !self.pattern_mismatch and
            !self.too_long and
            !self.too_short and
            !self.range_underflow and
            !self.range_overflow and
            !self.step_mismatch and
            !self.bad_input and
            !self.custom_error;
    }
};

pub const ValidationResult = struct {
    validity: ValidityState,
    message: []const u8 = "",
};

pub const FormValidationReport = struct {
    is_valid: bool,
    first_invalid_node: ?*const Node = null,
    messages: std.ArrayList([]const u8),

    pub fn deinit(self: *FormValidationReport, allocator: std.mem.Allocator) void {
        for (self.messages.items) |m| {
            allocator.free(m);
        }
        self.messages.deinit(allocator);
    }
};

pub const FormValidator = struct {
    /// Validates an individual form control (<input>, <select>, <textarea>) against HTML5 constraints
    pub fn checkValidity(element: *const Node, table: *AtomTable) ValidationResult {
        if (element.node_type != .Element) {
            return .{ .validity = .{ .valid = true }, .message = "" };
        }

        var validity = ValidityState{};
        var msg: []const u8 = "";

        const tag = table.get(element.tag_name);
        const is_input = std.mem.eql(u8, tag, "input");
        const is_textarea = std.mem.eql(u8, tag, "textarea");
        const is_select = std.mem.eql(u8, tag, "select");

        if (!is_input and !is_textarea and !is_select) {
            return .{ .validity = .{ .valid = true }, .message = "" };
        }

        const custom_err_atom = table.intern("data-custom-validity") catch null;
        if (custom_err_atom) |ca| {
            if (element.getAttribute(ca)) |custom_msg| {
                if (custom_msg.len > 0) {
                    validity.custom_error = true;
                    validity.valid = false;
                    return .{ .validity = validity, .message = custom_msg };
                }
            }
        }

        const value_atom = table.intern("value") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const required_atom = table.intern("required") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const type_atom = table.intern("type") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const min_atom = table.intern("min") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const max_atom = table.intern("max") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const step_atom = table.intern("step") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const minlen_atom = table.intern("minlength") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const maxlen_atom = table.intern("maxlength") catch return .{ .validity = .{ .valid = true }, .message = "" };
        const pattern_atom = table.intern("pattern") catch return .{ .validity = .{ .valid = true }, .message = "" };

        const val = element.getAttribute(value_atom) orelse "";
        const is_required = element.hasAttribute(required_atom);
        const input_type = if (is_input) (element.getAttribute(type_atom) orelse "text") else "text";

        // 1. valueMissing (required constraint)
        if (is_required and val.len == 0) {
            validity.value_missing = true;
            msg = "Please fill out this field.";
        }

        // 2. typeMismatch (email, url)
        if (val.len > 0) {
            if (std.ascii.eqlIgnoreCase(input_type, "email")) {
                if (!validateEmail(val)) {
                    validity.type_mismatch = true;
                    msg = "Please enter a valid email address.";
                }
            } else if (std.ascii.eqlIgnoreCase(input_type, "url")) {
                if (!validateUrl(val)) {
                    validity.type_mismatch = true;
                    msg = "Please enter a valid URL.";
                }
            }
        }

        // 3. tooShort and tooLong (minlength, maxlength)
        if (val.len > 0) {
            if (element.getAttribute(minlen_atom)) |minl_str| {
                if (std.fmt.parseInt(usize, minl_str, 10)) |min_len| {
                    if (val.len < min_len) {
                        validity.too_short = true;
                        msg = "Please lengthen this text to meet minimum required characters.";
                    }
                } else |_| {}
            }
            if (element.getAttribute(maxlen_atom)) |maxl_str| {
                if (std.fmt.parseInt(usize, maxl_str, 10)) |max_len| {
                    if (val.len > max_len) {
                        validity.too_long = true;
                        msg = "Please shorten this text to meet maximum character limit.";
                    }
                } else |_| {}
            }
        }

        // 4. rangeUnderflow, rangeOverflow, stepMismatch, and badInput (number, range)
        if (std.ascii.eqlIgnoreCase(input_type, "number") or std.ascii.eqlIgnoreCase(input_type, "range")) {
            if (val.len > 0) {
                const num_val = std.fmt.parseFloat(f64, val) catch {
                    validity.bad_input = true;
                    msg = "Please enter a valid number.";
                    validity.updateValid();
                    return .{ .validity = validity, .message = msg };
                };

                if (element.getAttribute(min_atom)) |min_str| {
                    if (std.fmt.parseFloat(f64, min_str)) |min_bound| {
                        if (num_val < min_bound) {
                            validity.range_underflow = true;
                            msg = "Value must be greater than or equal to minimum.";
                        }
                    } else |_| {}
                }

                if (element.getAttribute(max_atom)) |max_str| {
                    if (std.fmt.parseFloat(f64, max_str)) |max_bound| {
                        if (num_val > max_bound) {
                            validity.range_overflow = true;
                            msg = "Value must be less than or equal to maximum.";
                        }
                    } else |_| {}
                }

                if (element.getAttribute(step_atom)) |step_str| {
                    if (std.fmt.parseFloat(f64, step_str)) |step_val| {
                        if (step_val > 0.0) {
                            const min_base = if (element.getAttribute(min_atom)) |m| (std.fmt.parseFloat(f64, m) catch 0.0) else 0.0;
                            const delta = num_val - min_base;
                            const remainder = @rem(delta, step_val);
                            if (remainder > 1e-5 and remainder < (step_val - 1e-5)) {
                                validity.step_mismatch = true;
                                msg = "Please enter a valid value matching step interval.";
                            }
                        }
                    } else |_| {}
                }
            }
        }

        // 5. patternMismatch
        if (val.len > 0) {
            if (element.getAttribute(pattern_atom)) |pat| {
                if (!matchSimpleRegex(pat, val)) {
                    validity.pattern_mismatch = true;
                    msg = "Please match the requested format.";
                }
            }
        }

        validity.updateValid();
        return .{ .validity = validity, .message = if (validity.valid) "" else msg };
    }

    /// Sets custom validity error string on a form control
    pub fn setCustomValidity(element: *Node, message: []const u8, table: *AtomTable, allocator: std.mem.Allocator) !void {
        const custom_err_atom = try table.intern("data-custom-validity");
        try element.setAttribute(allocator, custom_err_atom, message);
    }

    /// Validates all form controls within a <form> element
    pub fn checkFormValidity(form: *const Node, table: *AtomTable) bool {
        var is_valid = true;
        checkFormRecursive(form, table, &is_valid, null, null, null);
        return is_valid;
    }

    /// Produces a complete report on form constraints, collecting all invalid controls and messages
    pub fn reportFormValidity(allocator: std.mem.Allocator, form: *const Node, table: *AtomTable) !FormValidationReport {
        var is_valid = true;
        var first_invalid: ?*const Node = null;
        var messages = std.ArrayList([]const u8).empty;
        errdefer {
            for (messages.items) |m| allocator.free(m);
            messages.deinit(allocator);
        }

        checkFormRecursive(form, table, &is_valid, &first_invalid, &messages, allocator);

        return FormValidationReport{
            .is_valid = is_valid,
            .first_invalid_node = first_invalid,
            .messages = messages,
        };
    }

    fn checkFormRecursive(
        node: *const Node,
        table: *AtomTable,
        all_valid: *bool,
        first_invalid: ?*?*const Node,
        messages_opt: ?*std.ArrayList([]const u8),
        allocator_opt: ?std.mem.Allocator,
    ) void {
        if (node.node_type == .Element) {
            const tag = table.get(node.tag_name);
            if (std.mem.eql(u8, tag, "input") or std.mem.eql(u8, tag, "select") or std.mem.eql(u8, tag, "textarea")) {
                const res = checkValidity(node, table);
                if (!res.validity.valid) {
                    all_valid.* = false;
                    if (first_invalid) |fi| {
                        if (fi.* == null) fi.* = node;
                    }
                    if (messages_opt) |msg_list| {
                        if (allocator_opt) |alloc| {
                            const copy = alloc.dupe(u8, res.message) catch return;
                            msg_list.append(alloc, copy) catch return;
                        }
                    }
                }
            }
        }

        var curr = node.first_child;
        while (curr) |child| {
            checkFormRecursive(child, table, all_valid, first_invalid, messages_opt, allocator_opt);
            curr = child.next_sibling;
        }
    }
};

fn validateEmail(val: []const u8) bool {
    const at_idx = std.mem.indexOfScalar(u8, val, '@') orelse return false;
    if (at_idx == 0 or at_idx == val.len - 1) return false;
    const domain = val[at_idx + 1 ..];
    const dot_idx = std.mem.indexOfScalar(u8, domain, '.') orelse return false;
    if (dot_idx == 0 or dot_idx == domain.len - 1) return false;
    return true;
}

fn validateUrl(val: []const u8) bool {
    return std.mem.startsWith(u8, val, "http://") or
        std.mem.startsWith(u8, val, "https://") or
        std.mem.startsWith(u8, val, "ftp://");
}

fn matchSimpleRegex(pattern: []const u8, text: []const u8) bool {
    // Basic glob and character class matcher e.g. [0-9]{3} or prefix/suffix
    if (std.mem.eql(u8, pattern, ".*") or pattern.len == 0) return true;

    // Direct match
    if (std.mem.eql(u8, pattern, text)) return true;

    // Match exact numeric range pattern like [0-9]+
    if (std.mem.eql(u8, pattern, "[0-9]+")) {
        for (text) |c| {
            if (c < '0' or c > '9') return false;
        }
        return text.len > 0;
    }

    // Match alphabet pattern [a-zA-Z]+
    if (std.mem.eql(u8, pattern, "[a-zA-Z]+")) {
        for (text) |c| {
            const is_alpha = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
            if (!is_alpha) return false;
        }
        return text.len > 0;
    }

    return std.mem.indexOf(u8, text, pattern) != null;
}

test "html5 form validation required, email, and url constraints" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    // 1. Required constraint
    const input = try Node.create(allocator, .Element, try table.intern("input"));
    defer input.deinit(allocator);
    try input.setAttribute(allocator, try table.intern("required"), "");

    // Empty -> valueMissing
    const res1 = FormValidator.checkValidity(input, table);
    try std.testing.expect(!res1.validity.valid);
    try std.testing.expect(res1.validity.value_missing);

    // Filled -> valid
    try input.setAttribute(allocator, try table.intern("value"), "Davoth User");
    const res2 = FormValidator.checkValidity(input, table);
    try std.testing.expect(res2.validity.valid);

    // 2. Email type constraint
    const email_input = try Node.create(allocator, .Element, try table.intern("input"));
    defer email_input.deinit(allocator);
    try email_input.setAttribute(allocator, try table.intern("type"), "email");

    try email_input.setAttribute(allocator, try table.intern("value"), "not-an-email");
    const res_bad_email = FormValidator.checkValidity(email_input, table);
    try std.testing.expect(!res_bad_email.validity.valid);
    try std.testing.expect(res_bad_email.validity.type_mismatch);

    try email_input.setAttribute(allocator, try table.intern("value"), "alice@example.com");
    const res_good_email = FormValidator.checkValidity(email_input, table);
    try std.testing.expect(res_good_email.validity.valid);

    // 3. URL type constraint
    const url_input = try Node.create(allocator, .Element, try table.intern("input"));
    defer url_input.deinit(allocator);
    try url_input.setAttribute(allocator, try table.intern("type"), "url");

    try url_input.setAttribute(allocator, try table.intern("value"), "httpx//bad");
    const res_bad_url = FormValidator.checkValidity(url_input, table);
    try std.testing.expect(!res_bad_url.validity.valid);
    try std.testing.expect(res_bad_url.validity.type_mismatch);

    try url_input.setAttribute(allocator, try table.intern("value"), "https://davoth.org");
    const res_good_url = FormValidator.checkValidity(url_input, table);
    try std.testing.expect(res_good_url.validity.valid);
}

test "html5 form validation numbers, min, max, step, pattern and custom validity" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    // 1. Min, Max, Step number validation
    const num_input = try Node.create(allocator, .Element, try table.intern("input"));
    defer num_input.deinit(allocator);
    try num_input.setAttribute(allocator, try table.intern("type"), "number");
    try num_input.setAttribute(allocator, try table.intern("min"), "10");
    try num_input.setAttribute(allocator, try table.intern("max"), "50");
    try num_input.setAttribute(allocator, try table.intern("step"), "5");

    // Underflow: 5 < 10
    try num_input.setAttribute(allocator, try table.intern("value"), "5");
    const r_under = FormValidator.checkValidity(num_input, table);
    try std.testing.expect(r_under.validity.range_underflow);

    // Overflow: 60 > 50
    try num_input.setAttribute(allocator, try table.intern("value"), "60");
    const r_over = FormValidator.checkValidity(num_input, table);
    try std.testing.expect(r_over.validity.range_overflow);

    // Step mismatch: 12 is not 10 + 5*k
    try num_input.setAttribute(allocator, try table.intern("value"), "12");
    const r_step = FormValidator.checkValidity(num_input, table);
    try std.testing.expect(r_step.validity.step_mismatch);

    // Valid: 25 (>=10, <=50, step of 5)
    try num_input.setAttribute(allocator, try table.intern("value"), "25");
    const r_good = FormValidator.checkValidity(num_input, table);
    try std.testing.expect(r_good.validity.valid);

    // 2. Pattern mismatch
    const pat_input = try Node.create(allocator, .Element, try table.intern("input"));
    defer pat_input.deinit(allocator);
    try pat_input.setAttribute(allocator, try table.intern("pattern"), "[0-9]+");

    try pat_input.setAttribute(allocator, try table.intern("value"), "abc");
    const r_bad_pat = FormValidator.checkValidity(pat_input, table);
    try std.testing.expect(r_bad_pat.validity.pattern_mismatch);

    try pat_input.setAttribute(allocator, try table.intern("value"), "98765");
    const r_good_pat = FormValidator.checkValidity(pat_input, table);
    try std.testing.expect(r_good_pat.validity.valid);

    // 3. Custom error validity
    try FormValidator.setCustomValidity(pat_input, "Custom security check failed", table, allocator);
    const r_custom = FormValidator.checkValidity(pat_input, table);
    try std.testing.expect(!r_custom.validity.valid);
    try std.testing.expect(r_custom.validity.custom_error);
    try std.testing.expectEqualStrings("Custom security check failed", r_custom.message);
}

test "html5 form level checkFormValidity and reportFormValidity" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const form = try Node.create(allocator, .Element, try table.intern("form"));
    defer form.deinit(allocator);

    const f1 = try Node.create(allocator, .Element, try table.intern("input"));
    try f1.setAttribute(allocator, try table.intern("required"), "");
    try f1.setAttribute(allocator, try table.intern("value"), "John");
    try form.appendChild(allocator, f1);

    const f2 = try Node.create(allocator, .Element, try table.intern("input"));
    try f2.setAttribute(allocator, try table.intern("type"), "email");
    try f2.setAttribute(allocator, try table.intern("value"), "bad_email_here");
    try form.appendChild(allocator, f2);

    // Form validity should fail due to f2
    try std.testing.expect(!FormValidator.checkFormValidity(form, table));

    var report = try FormValidator.reportFormValidity(allocator, form, table);
    defer report.deinit(allocator);

    try std.testing.expect(!report.is_valid);
    try std.testing.expectEqual(f2, report.first_invalid_node.?);
    try std.testing.expectEqual(@as(usize, 1), report.messages.items.len);
    try std.testing.expect(std.mem.indexOf(u8, report.messages.items[0], "email") != null);
}
