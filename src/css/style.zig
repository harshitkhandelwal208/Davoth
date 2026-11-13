//! Cascading, inheritance, and ComputedStyle resolution.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const Color = @import("../common/types.zig").Color;
const Node = @import("../dom/node.zig").Node;
const StyleSheet = @import("parser.zig").StyleSheet;
const Rule = @import("parser.zig").Rule;
const ComputedStyle = @import("properties.zig").ComputedStyle;
const Display = @import("properties.zig").Display;
const Position = @import("properties.zig").Position;
const FlexDirection = @import("properties.zig").FlexDirection;
const JustifyContent = @import("properties.zig").JustifyContent;
const AlignItems = @import("properties.zig").AlignItems;
const UnitValue = @import("properties.zig").UnitValue;

pub const MatchedRule = struct {
    specificity: u32,
    rule: *const Rule,
};

pub const StyleEngine = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    ua_stylesheet: StyleSheet,
    author_stylesheets: std.ArrayList(StyleSheet),
    custom_properties: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable) !*StyleEngine {
        const engine = try allocator.create(StyleEngine);
        const CSSParser = @import("parser.zig").CSSParser;

        // User-agent default stylesheet
        const ua_css =
            \\html, body { display: block; margin: 0px; padding: 0px; }
            \\div, p, h1, h2, h3, h4, h5, h6, ul, ol, li, section, header, footer { display: block; }
            \\span, a, strong, em, b, i { display: inline; }
            \\img { display: inline-block; }
            \\button { display: inline-block; cursor: pointer; }
        ;

        var parser = CSSParser.init(allocator, atom_table, ua_css);
        const ua_sheet = try parser.parse();

        engine.* = .{
            .allocator = allocator,
            .atom_table = atom_table,
            .ua_stylesheet = ua_sheet,
            .author_stylesheets = .empty,
            .custom_properties = std.StringHashMap([]const u8).init(allocator),
        };
        return engine;
    }

    pub fn deinit(self: *StyleEngine) void {
        self.ua_stylesheet.deinit();
        for (self.author_stylesheets.items) |*sheet| {
            sheet.deinit();
        }
        self.author_stylesheets.deinit(self.allocator);

        var it = self.custom_properties.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.custom_properties.deinit();

        self.allocator.destroy(self);
    }

    pub fn setCustomProperty(self: *StyleEngine, name: []const u8, value: []const u8) !void {
        if (self.custom_properties.getEntry(name)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = try self.allocator.dupe(u8, value);
            return;
        }
        const k = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(k);
        const v = try self.allocator.dupe(u8, value);
        try self.custom_properties.put(k, v);
    }

    pub fn resolveVar(self: *StyleEngine, val: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "var(") and std.mem.endsWith(u8, trimmed, ")")) {
            const inner = trimmed[4 .. trimmed.len - 1];
            if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                const var_name = std.mem.trim(u8, inner[0..comma], " \t\r\n");
                const fallback = std.mem.trim(u8, inner[comma + 1 ..], " \t\r\n");
                if (self.custom_properties.get(var_name)) |resolved| {
                    return resolved;
                }
                return fallback;
            } else {
                const var_name = std.mem.trim(u8, inner, " \t\r\n");
                if (self.custom_properties.get(var_name)) |resolved| {
                    return resolved;
                }
                return "";
            }
        }
        return trimmed;
    }

    pub fn addAuthorStylesheet(self: *StyleEngine, css: []const u8) !void {
        const CSSParser = @import("parser.zig").CSSParser;
        var parser = CSSParser.init(self.allocator, self.atom_table, css);
        const sheet = try parser.parse();
        try self.author_stylesheets.append(self.allocator, sheet);
    }

    pub fn computeStyle(self: *StyleEngine, node: *const Node, parent_style: ?*const ComputedStyle) !ComputedStyle {
        var style = ComputedStyle{};

        // 1. Inherit inheritable properties from parent
        if (parent_style) |parent| {
            style.color = parent.color;
            style.font_size = parent.font_size;
            style.line_height = parent.line_height;
        }

        if (node.node_type != .Element) return style;

        // 2. Gather matched rules from UA and Author stylesheets
        var matched: std.ArrayList(MatchedRule) = .empty;
        defer matched.deinit(self.allocator);

        // Match UA rules
        for (self.ua_stylesheet.rules.items) |*rule| {
            if (rule.selector.matches(node, self.atom_table)) {
                try matched.append(self.allocator, .{
                    .specificity = 0, // UA specificity lower than author
                    .rule = rule,
                });
            }
        }

        // Match Author rules
        for (self.author_stylesheets.items) |*sheet| {
            for (sheet.rules.items) |*rule| {
                if (rule.selector.matches(node, self.atom_table)) {
                    try matched.append(self.allocator, .{
                        .specificity = rule.selector.calculateSpecificity(),
                        .rule = rule,
                    });
                }
            }
        }

        // Sort by specificity
        const Sorter = struct {
            fn lessThan(_: void, a: MatchedRule, b: MatchedRule) bool {
                return a.specificity < b.specificity;
            }
        };
        std.mem.sort(MatchedRule, matched.items, {}, Sorter.lessThan);

        // Apply rules in order
        for (matched.items) |m| {
            for (m.rule.declarations.items) |decl| {
                try self.applyDeclaration(&style, decl.property, decl.value);
            }
        }

        // 3. Inline style attribute (specificity 100000)
        const style_atom = try self.atom_table.intern("style");
        if (node.getAttribute(style_atom)) |inline_css| {
            var it = std.mem.splitScalar(u8, inline_css, ';');
            while (it.next()) |decl_str| {
                const trimmed = std.mem.trim(u8, decl_str, " \t\r\n");
                if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                    const prop_str = std.mem.trim(u8, trimmed[0..colon], " \t\r\n");
                    const val_str = std.mem.trim(u8, trimmed[colon + 1 ..], " \t\r\n");
                    const prop_atom = try self.atom_table.intern(prop_str);
                    try self.applyDeclaration(&style, prop_atom, val_str);
                }
            }
        }

        return style;
    }

    fn applyDeclaration(self: *StyleEngine, style: *ComputedStyle, prop: AtomId, raw_val: []const u8) !void {
        const name = self.atom_table.get(prop);

        // Custom property definition (--variable-name: value)
        if (std.mem.startsWith(u8, name, "--")) {
            try self.setCustomProperty(name, raw_val);
            return;
        }

        // Variable substitution (var(--variable-name, fallback))
        const val = self.resolveVar(raw_val);
        if (val.len == 0) return;

        if (std.mem.eql(u8, name, "display")) {
            if (std.mem.eql(u8, val, "block")) style.display = .Block;
            if (std.mem.eql(u8, val, "inline")) style.display = .Inline;
            if (std.mem.eql(u8, val, "inline-block")) style.display = .InlineBlock;
            if (std.mem.eql(u8, val, "flex")) style.display = .Flex;
            if (std.mem.eql(u8, val, "grid")) style.display = .Grid;
            if (std.mem.eql(u8, val, "none")) style.display = .None;
        } else if (std.mem.eql(u8, name, "position")) {
            if (std.mem.eql(u8, val, "static")) style.position = .Static;
            if (std.mem.eql(u8, val, "relative")) style.position = .Relative;
            if (std.mem.eql(u8, val, "absolute")) style.position = .Absolute;
            if (std.mem.eql(u8, val, "fixed")) style.position = .Fixed;
            if (std.mem.eql(u8, val, "sticky")) style.position = .Sticky;
        } else if (std.mem.eql(u8, name, "box-sizing")) {
            if (std.mem.eql(u8, val, "border-box")) style.box_sizing = .BorderBox;
            if (std.mem.eql(u8, val, "content-box")) style.box_sizing = .ContentBox;
        } else if (std.mem.eql(u8, name, "background-color") or std.mem.eql(u8, name, "background")) {
            if (Color.parse(val)) |col| {
                style.background_color = col;
            }
        } else if (std.mem.eql(u8, name, "color")) {
            if (Color.parse(val)) |col| {
                style.color = col;
            }
        } else if (std.mem.eql(u8, name, "border-color")) {
            if (Color.parse(val)) |col| {
                style.border_color = col;
            }
        } else if (std.mem.eql(u8, name, "border-width") or std.mem.eql(u8, name, "border")) {
            const u = parseUnit(val);
            style.border_widths = @import("../common/types.zig").BoxEdges.initAll(u.value);
            // If shorthand contains a color token
            if (Color.parse(val)) |col| {
                style.border_color = col;
            }
        } else if (std.mem.eql(u8, name, "width")) {
            style.width = parseUnit(val);
        } else if (std.mem.eql(u8, name, "height")) {
            style.height = parseUnit(val);
        } else if (std.mem.eql(u8, name, "min-width")) {
            style.min_width = parseUnit(val);
        } else if (std.mem.eql(u8, name, "max-width")) {
            style.max_width = parseUnit(val);
        } else if (std.mem.eql(u8, name, "min-height")) {
            style.min_height = parseUnit(val);
        } else if (std.mem.eql(u8, name, "max-height")) {
            style.max_height = parseUnit(val);
        } else if (std.mem.eql(u8, name, "margin")) {
            const u = parseUnit(val);
            style.margin = .{ .top = u, .right = u, .bottom = u, .left = u };
        } else if (std.mem.eql(u8, name, "padding")) {
            const u = parseUnit(val);
            style.padding = .{ .top = u, .right = u, .bottom = u, .left = u };
        } else if (std.mem.eql(u8, name, "top")) {
            style.top = parseUnit(val);
        } else if (std.mem.eql(u8, name, "right")) {
            style.right = parseUnit(val);
        } else if (std.mem.eql(u8, name, "bottom")) {
            style.bottom = parseUnit(val);
        } else if (std.mem.eql(u8, name, "left")) {
            style.left = parseUnit(val);
        } else if (std.mem.eql(u8, name, "flex-direction")) {
            if (std.mem.eql(u8, val, "row")) style.flex_direction = .Row;
            if (std.mem.eql(u8, val, "row-reverse")) style.flex_direction = .RowReverse;
            if (std.mem.eql(u8, val, "column")) style.flex_direction = .Column;
            if (std.mem.eql(u8, val, "column-reverse")) style.flex_direction = .ColumnReverse;
        } else if (std.mem.eql(u8, name, "justify-content")) {
            if (std.mem.eql(u8, val, "flex-start")) style.justify_content = .FlexStart;
            if (std.mem.eql(u8, val, "flex-end")) style.justify_content = .FlexEnd;
            if (std.mem.eql(u8, val, "center")) style.justify_content = .Center;
            if (std.mem.eql(u8, val, "space-between")) style.justify_content = .SpaceBetween;
            if (std.mem.eql(u8, val, "space-around")) style.justify_content = .SpaceAround;
            if (std.mem.eql(u8, val, "space-evenly")) style.justify_content = .SpaceEvenly;
        } else if (std.mem.eql(u8, name, "align-items")) {
            if (std.mem.eql(u8, val, "stretch")) style.align_items = .Stretch;
            if (std.mem.eql(u8, val, "flex-start")) style.align_items = .FlexStart;
            if (std.mem.eql(u8, val, "flex-end")) style.align_items = .FlexEnd;
            if (std.mem.eql(u8, val, "center")) style.align_items = .Center;
            if (std.mem.eql(u8, val, "baseline")) style.align_items = .Baseline;
        } else if (std.mem.eql(u8, name, "flex-grow")) {
            style.flex_grow = std.fmt.parseFloat(f32, val) catch 0.0;
        } else if (std.mem.eql(u8, name, "flex-shrink")) {
            style.flex_shrink = std.fmt.parseFloat(f32, val) catch 1.0;
        } else if (std.mem.eql(u8, name, "flex-basis")) {
            style.flex_basis = parseUnit(val);
        } else if (std.mem.eql(u8, name, "opacity")) {
            const op = std.fmt.parseFloat(f32, val) catch 1.0;
            style.opacity = @max(0.0, @min(1.0, op));
        } else if (std.mem.eql(u8, name, "z-index")) {
            style.z_index = std.fmt.parseInt(i32, val, 10) catch 0;
        } else if (std.mem.eql(u8, name, "font-size")) {
            style.font_size = parseUnit(val).value;
        } else if (std.mem.eql(u8, name, "line-height")) {
            style.line_height = std.fmt.parseFloat(f32, val) catch 1.2;
        }
    }

    fn parseUnit(val: []const u8) UnitValue {
        if (std.mem.eql(u8, val, "auto")) return UnitValue.auto;
        if (std.mem.endsWith(u8, val, "px")) {
            const num = std.fmt.parseFloat(f32, val[0 .. val.len - 2]) catch 0.0;
            return UnitValue.px(num);
        }
        if (std.mem.endsWith(u8, val, "%")) {
            const num = std.fmt.parseFloat(f32, val[0 .. val.len - 1]) catch 0.0;
            return UnitValue.percent(num);
        }
        const num = std.fmt.parseFloat(f32, val) catch 0.0;
        return UnitValue.px(num);
    }
};

test "style engine compute style with cascade" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const engine = try StyleEngine.init(allocator, table);
    defer engine.deinit();

    try engine.addAuthorStylesheet("div.banner { background-color: #0000ff; width: 300px; }");

    const node = try Node.create(allocator, .Element, try table.intern("div"));
    defer node.deinit(allocator);
    try node.setAttribute(allocator, try table.intern("class"), "banner");

    const computed = try engine.computeStyle(node, null);
    try std.testing.expectEqual(Display.Block, computed.display); // from UA
    try std.testing.expectEqual(@as(u8, 255), computed.background_color.b); // #0000ff
    try std.testing.expectEqual(@as(f32, 300.0), computed.width.value);
}

test "style engine css custom properties and var resolution" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const engine = try StyleEngine.init(allocator, table);
    defer engine.deinit();

    try engine.addAuthorStylesheet(
        \\div.theme-card {
        \\  --theme-bg: #123456;
        \\  --theme-pad: 20px;
        \\  background-color: var(--theme-bg);
        \\  padding: var(--theme-pad);
        \\  color: var(--missing-color, #ffffff);
        \\}
    );

    const node = try Node.create(allocator, .Element, try table.intern("div"));
    defer node.deinit(allocator);
    try node.setAttribute(allocator, try table.intern("class"), "theme-card");

    const computed = try engine.computeStyle(node, null);
    try std.testing.expectEqual(@as(u8, 0x12), computed.background_color.r);
    try std.testing.expectEqual(@as(u8, 0x34), computed.background_color.g);
    try std.testing.expectEqual(@as(u8, 0x56), computed.background_color.b);
    try std.testing.expectEqual(@as(f32, 20.0), computed.padding.top.value);
    try std.testing.expectEqual(@as(u8, 255), computed.color.r); // fallback #ffffff
    try std.testing.expectEqual(@as(u8, 255), computed.color.g);
    try std.testing.expectEqual(@as(u8, 255), computed.color.b);
}
