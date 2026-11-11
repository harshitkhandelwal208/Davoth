//! CSS tokenizer.
const std = @import("std");

pub const CSSTokenType = enum {
    Ident,
    Number,
    Dimension,
    Percentage,
    Hash,
    String,
    Colon,
    Semicolon,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Comma,
    Dot,
    Star,
    Greater,
    Plus,
    Tilde,
    EOF,
};

pub const CSSToken = struct {
    token_type: CSSTokenType,
    lexeme: []const u8,
    unit: []const u8 = "",
    number_value: f32 = 0.0,
};

pub const CSSLexer = struct {
    source: []const u8,
    cursor: usize = 0,

    pub fn init(source: []const u8) CSSLexer {
        return .{ .source = source, .cursor = 0 };
    }

    pub fn nextToken(self: *CSSLexer) CSSToken {
        self.skipWhitespaceAndComments();

        if (self.cursor >= self.source.len) {
            return .{ .token_type = .EOF, .lexeme = "" };
        }

        const ch = self.source[self.cursor];

        if (ch == '#') {
            self.cursor += 1;
            const start = self.cursor;
            while (self.cursor < self.source.len and (std.ascii.isAlphanumeric(self.source[self.cursor]) or self.source[self.cursor] == '-' or self.source[self.cursor] == '_')) {
                self.cursor += 1;
            }
            return .{ .token_type = .Hash, .lexeme = self.source[start..self.cursor] };
        }

        if (ch == '.') {
            self.cursor += 1;
            return .{ .token_type = .Dot, .lexeme = "." };
        }

        if (ch == ':') {
            self.cursor += 1;
            return .{ .token_type = .Colon, .lexeme = ":" };
        }

        if (ch == ';') {
            self.cursor += 1;
            return .{ .token_type = .Semicolon, .lexeme = ";" };
        }

        if (ch == '{') {
            self.cursor += 1;
            return .{ .token_type = .LBrace, .lexeme = "{" };
        }

        if (ch == '}') {
            self.cursor += 1;
            return .{ .token_type = .RBrace, .lexeme = "}" };
        }

        if (ch == '[') {
            self.cursor += 1;
            return .{ .token_type = .LBracket, .lexeme = "[" };
        }

        if (ch == ']') {
            self.cursor += 1;
            return .{ .token_type = .RBracket, .lexeme = "]" };
        }

        if (ch == ',') {
            self.cursor += 1;
            return .{ .token_type = .Comma, .lexeme = "," };
        }

        if (ch == '*') {
            self.cursor += 1;
            return .{ .token_type = .Star, .lexeme = "*" };
        }

        if (ch == '>') {
            self.cursor += 1;
            return .{ .token_type = .Greater, .lexeme = ">" };
        }

        if (ch == '+') {
            self.cursor += 1;
            return .{ .token_type = .Plus, .lexeme = "+" };
        }

        if (ch == '~') {
            self.cursor += 1;
            return .{ .token_type = .Tilde, .lexeme = "~" };
        }

        if (std.ascii.isDigit(ch) or (ch == '-' and self.cursor + 1 < self.source.len and std.ascii.isDigit(self.source[self.cursor + 1]))) {
            return self.readNumberOrDimension();
        }

        if (std.ascii.isAlphabetic(ch) or ch == '-' or ch == '_') {
            const start = self.cursor;
            while (self.cursor < self.source.len and (std.ascii.isAlphanumeric(self.source[self.cursor]) or self.source[self.cursor] == '-' or self.source[self.cursor] == '_')) {
                self.cursor += 1;
            }
            return .{ .token_type = .Ident, .lexeme = self.source[start..self.cursor] };
        }

        if (ch == '"' or ch == '\'') {
            const quote = ch;
            self.cursor += 1;
            const start = self.cursor;
            while (self.cursor < self.source.len and self.source[self.cursor] != quote) {
                self.cursor += 1;
            }
            const lex = self.source[start..self.cursor];
            if (self.cursor < self.source.len) self.cursor += 1;
            return .{ .token_type = .String, .lexeme = lex };
        }

        self.cursor += 1;
        return .{ .token_type = .EOF, .lexeme = "" };
    }

    fn skipWhitespaceAndComments(self: *CSSLexer) void {
        while (self.cursor < self.source.len) {
            const c = self.source[self.cursor];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.cursor += 1;
            } else if (c == '/' and self.cursor + 1 < self.source.len and self.source[self.cursor + 1] == '*') {
                self.cursor += 2;
                while (self.cursor + 1 < self.source.len) {
                    if (self.source[self.cursor] == '*' and self.source[self.cursor + 1] == '/') {
                        self.cursor += 2;
                        break;
                    }
                    self.cursor += 1;
                }
            } else {
                break;
            }
        }
    }

    fn readNumberOrDimension(self: *CSSLexer) CSSToken {
        const start = self.cursor;
        if (self.source[self.cursor] == '-') self.cursor += 1;

        while (self.cursor < self.source.len and (std.ascii.isDigit(self.source[self.cursor]) or self.source[self.cursor] == '.')) {
            self.cursor += 1;
        }
        const num_str = self.source[start..self.cursor];
        const num_val = std.fmt.parseFloat(f32, num_str) catch 0.0;

        if (self.cursor < self.source.len and self.source[self.cursor] == '%') {
            self.cursor += 1;
            return .{ .token_type = .Percentage, .lexeme = num_str, .unit = "%", .number_value = num_val };
        }

        const unit_start = self.cursor;
        while (self.cursor < self.source.len and std.ascii.isAlphabetic(self.source[self.cursor])) {
            self.cursor += 1;
        }

        if (self.cursor > unit_start) {
            return .{
                .token_type = .Dimension,
                .lexeme = num_str,
                .unit = self.source[unit_start..self.cursor],
                .number_value = num_val,
            };
        }

        return .{
            .token_type = .Number,
            .lexeme = num_str,
            .number_value = num_val,
        };
    }
};

test "css lexer tokenize rules" {
    const css = "body { margin: 0px; background-color: #ffffff; }";
    var lexer = CSSLexer.init(css);

    const t1 = lexer.nextToken();
    try std.testing.expectEqual(CSSTokenType.Ident, t1.token_type);
    try std.testing.expectEqualStrings("body", t1.lexeme);

    const t2 = lexer.nextToken();
    try std.testing.expectEqual(CSSTokenType.LBrace, t2.token_type);
}
