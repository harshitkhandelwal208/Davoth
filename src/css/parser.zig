//! CSS Stylesheet and rule parser.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const CSSLexer = @import("lexer.zig").CSSLexer;
const CSSTokenType = @import("lexer.zig").CSSTokenType;
const Selector = @import("selector.zig").Selector;
const SimpleSelector = @import("selector.zig").SimpleSelector;
const ComplexSelectorPart = @import("selector.zig").ComplexSelectorPart;

pub const Declaration = struct {
    property: AtomId,
    value: []const u8,
    important: bool = false,
};

pub const Rule = struct {
    selector: Selector,
    declarations: std.ArrayList(Declaration),

    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        self.selector.deinit();
        for (self.declarations.items) |decl| {
            allocator.free(decl.value);
        }
        self.declarations.deinit(allocator);
    }
};

pub const StyleSheet = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(Rule),

    pub fn init(allocator: std.mem.Allocator) StyleSheet {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    pub fn deinit(self: *StyleSheet) void {
        for (self.rules.items) |*r| {
            r.deinit(self.allocator);
        }
        self.rules.deinit(self.allocator);
    }
};

pub const CSSParser = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    lexer: CSSLexer,

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable, source: []const u8) CSSParser {
        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .lexer = CSSLexer.init(source),
        };
    }

    pub fn parse(self: *CSSParser) !StyleSheet {
        var sheet = StyleSheet.init(self.allocator);
        errdefer sheet.deinit();

        while (true) {
            const rule_opt = try self.parseRule();
            if (rule_opt) |rule| {
                try sheet.rules.append(self.allocator, rule);
            } else {
                break;
            }
        }

        return sheet;
    }

    fn parseRule(self: *CSSParser) !?Rule {
        var selector = Selector.init(self.allocator);
        errdefer selector.deinit();

        var part = ComplexSelectorPart{
            .selector = SimpleSelector.init(self.allocator),
            .combinator = .None,
        };

        var has_selector = false;

        while (true) {
            const tok = self.lexer.nextToken();
            if (tok.token_type == .EOF) {
                part.selector.deinit(self.allocator);
                return null;
            }

            if (tok.token_type == .LBrace) {
                break;
            }

            if (tok.token_type == .Ident) {
                const tag_lower = try self.allocator.dupe(u8, tok.lexeme);
                defer self.allocator.free(tag_lower);
                for (tag_lower) |*c| c.* = std.ascii.toLower(c.*);

                part.selector.tag_name = try self.atom_table.intern(tag_lower);
                has_selector = true;
            } else if (tok.token_type == .Dot) {
                const class_tok = self.lexer.nextToken();
                if (class_tok.token_type == .Ident) {
                    try part.selector.class_names.append(self.allocator, class_tok.lexeme);
                    has_selector = true;
                }
            } else if (tok.token_type == .Hash) {
                part.selector.id = tok.lexeme;
                has_selector = true;
            } else if (tok.token_type == .Greater) {
                part.combinator = .Child;
                try selector.parts.append(self.allocator, part);
                part = .{
                    .selector = SimpleSelector.init(self.allocator),
                    .combinator = .None,
                };
            }
        }

        if (!has_selector) {
            part.selector.deinit(self.allocator);
            return null;
        }

        try selector.parts.append(self.allocator, part);

        var declarations: std.ArrayList(Declaration) = .empty;
        errdefer declarations.deinit(self.allocator);

        // Parse declarations inside { ... }
        while (true) {
            const tok = self.lexer.nextToken();
            if (tok.token_type == .RBrace or tok.token_type == .EOF) break;

            if (tok.token_type == .Ident) {
                const prop_name_lower = try self.allocator.dupe(u8, tok.lexeme);
                defer self.allocator.free(prop_name_lower);
                for (prop_name_lower) |*c| c.* = std.ascii.toLower(c.*);

                const prop_atom = try self.atom_table.intern(prop_name_lower);

                const colon = self.lexer.nextToken();
                if (colon.token_type != .Colon) continue;

                // Read value until ';' or '}'
                const val_start = self.lexer.cursor;
                var is_important = false;

                while (self.lexer.cursor < self.lexer.source.len) {
                    const c = self.lexer.source[self.lexer.cursor];
                    if (c == ';' or c == '}') break;
                    self.lexer.cursor += 1;
                }

                var val_str = std.mem.trim(u8, self.lexer.source[val_start..self.lexer.cursor], " \t\r\n");
                if (std.mem.endsWith(u8, val_str, "!important")) {
                    is_important = true;
                    val_str = std.mem.trim(u8, val_str[0 .. val_str.len - 10], " \t\r\n");
                }

                if (self.lexer.cursor < self.lexer.source.len and self.lexer.source[self.lexer.cursor] == ';') {
                    self.lexer.cursor += 1;
                }

                try declarations.append(self.allocator, .{
                    .property = prop_atom,
                    .value = try self.allocator.dupe(u8, val_str),
                    .important = is_important,
                });
            }
        }

        return Rule{
            .selector = selector,
            .declarations = declarations,
        };
    }
};

test "css parser parse stylesheet" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const css =
        \\div.card {
        \\    display: flex;
        \\    background-color: #ff0000;
        \\    width: 250px;
        \\}
    ;

    var parser = CSSParser.init(allocator, table, css);
    var sheet = try parser.parse();
    defer sheet.deinit();

    try std.testing.expectEqual(@as(usize, 1), sheet.rules.items.len);
    try std.testing.expectEqual(@as(usize, 3), sheet.rules.items[0].declarations.items.len);
}
