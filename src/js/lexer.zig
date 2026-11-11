//! Full ECMAScript lexical analyzer.
const std = @import("std");

pub const TokenType = enum {
    Eof,
    Identifier,
    Number,
    String,
    TemplateString,

    // Keywords
    KwLet,
    KwConst,
    KwVar,
    KwFunction,
    KwReturn,
    KwIf,
    KwElse,
    KwWhile,
    KwFor,
    KwBreak,
    KwContinue,
    KwNew,
    KwThis,
    KwTypeof,
    KwInstanceof,
    KwTry,
    KwCatch,
    KwFinally,
    KwThrow,
    KwClass,
    KwAsync,
    KwAwait,
    KwImport,
    KwExport,
    KwDefault,
    KwTrue,
    KwFalse,
    KwNull,
    KwUndefined,

    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Equal,
    EqualEqual,
    EqualEqualEqual,
    Bang,
    BangEqual,
    BangEqualEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    AmpersandAmpersand,
    PipePipe,
    QuestionQuestion,
    Question,
    Colon,
    Dot,
    Arrow, // =>
    Spread, // ...

    // Delimiters
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Semicolon,
    Comma,
};

pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    line: u32,
    col: u32,
    num_value: f64 = 0.0,
};

pub const Lexer = struct {
    source: []const u8,
    cursor: usize = 0,
    line: u32 = 1,
    col: u32 = 1,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source, .cursor = 0, .line = 1, .col = 1 };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.cursor >= self.source.len) {
            return Token{
                .token_type = .Eof,
                .lexeme = "",
                .line = self.line,
                .col = self.col,
            };
        }

        const start_col = self.col;
        const start_line = self.line;
        const ch = self.peek();

        if (isIdentStart(ch)) {
            return self.readIdentifierOrKeyword(start_line, start_col);
        }

        if (std.ascii.isDigit(ch) or (ch == '.' and self.cursor + 1 < self.source.len and std.ascii.isDigit(self.source[self.cursor + 1]))) {
            return self.readNumber(start_line, start_col);
        }

        if (ch == '"' or ch == '\'') {
            return self.readString(start_line, start_col, ch);
        }

        if (ch == '`') {
            return self.readTemplateLiteral(start_line, start_col);
        }

        return self.readPunctuation(start_line, start_col);
    }

    fn peek(self: *Lexer) u8 {
        if (self.cursor < self.source.len) return self.source[self.cursor];
        return 0;
    }

    fn advance(self: *Lexer) u8 {
        if (self.cursor < self.source.len) {
            const ch = self.source[self.cursor];
            self.cursor += 1;
            if (ch == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            return ch;
        }
        return 0;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.cursor < self.source.len) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                _ = self.advance();
            } else if (c == '/' and self.cursor + 1 < self.source.len) {
                const next_c = self.source[self.cursor + 1];
                if (next_c == '/') {
                    // Line comment
                    _ = self.advance();
                    _ = self.advance();
                    while (self.cursor < self.source.len and self.peek() != '\n') {
                        _ = self.advance();
                    }
                } else if (next_c == '*') {
                    // Block comment
                    _ = self.advance();
                    _ = self.advance();
                    while (self.cursor + 1 < self.source.len) {
                        if (self.source[self.cursor] == '*' and self.source[self.cursor + 1] == '/') {
                            _ = self.advance();
                            _ = self.advance();
                            break;
                        }
                        _ = self.advance();
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        }
    }

    fn readIdentifierOrKeyword(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.cursor;
        while (self.cursor < self.source.len and isIdentPart(self.peek())) {
            _ = self.advance();
        }
        const lexeme = self.source[start..self.cursor];
        const tt = matchKeyword(lexeme);
        return Token{
            .token_type = tt,
            .lexeme = lexeme,
            .line = start_line,
            .col = start_col,
        };
    }

    fn readNumber(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.cursor;
        if (self.peek() == '0' and self.cursor + 1 < self.source.len) {
            const second = self.source[self.cursor + 1];
            if (second == 'x' or second == 'X') {
                _ = self.advance();
                _ = self.advance();
                while (self.cursor < self.source.len and std.ascii.isHex(self.peek())) {
                    _ = self.advance();
                }
                const lex = self.source[start..self.cursor];
                const val = std.fmt.parseInt(i64, lex[2..], 16) catch 0;
                return Token{
                    .token_type = .Number,
                    .lexeme = lex,
                    .line = start_line,
                    .col = start_col,
                    .num_value = @floatFromInt(val),
                };
            }
        }

        var has_dot = false;
        while (self.cursor < self.source.len) {
            const c = self.peek();
            if (std.ascii.isDigit(c)) {
                _ = self.advance();
            } else if (c == '.' and !has_dot) {
                has_dot = true;
                _ = self.advance();
            } else {
                break;
            }
        }

        const lex = self.source[start..self.cursor];
        const val = std.fmt.parseFloat(f64, lex) catch 0.0;
        return Token{
            .token_type = .Number,
            .lexeme = lex,
            .line = start_line,
            .col = start_col,
            .num_value = val,
        };
    }

    fn readString(self: *Lexer, start_line: u32, start_col: u32, quote: u8) Token {
        _ = self.advance(); // skip quote
        const start = self.cursor;
        while (self.cursor < self.source.len and self.peek() != quote) {
            if (self.peek() == '\\' and self.cursor + 1 < self.source.len) {
                _ = self.advance();
            }
            _ = self.advance();
        }
        const lex = self.source[start..self.cursor];
        if (self.cursor < self.source.len) _ = self.advance(); // skip closing quote

        return Token{
            .token_type = .String,
            .lexeme = lex,
            .line = start_line,
            .col = start_col,
        };
    }

    fn readTemplateLiteral(self: *Lexer, start_line: u32, start_col: u32) Token {
        _ = self.advance(); // skip backtick
        const start = self.cursor;
        while (self.cursor < self.source.len and self.peek() != '`') {
            if (self.peek() == '\\' and self.cursor + 1 < self.source.len) {
                _ = self.advance();
            }
            _ = self.advance();
        }
        const lex = self.source[start..self.cursor];
        if (self.cursor < self.source.len) _ = self.advance(); // skip backtick

        return Token{
            .token_type = .TemplateString,
            .lexeme = lex,
            .line = start_line,
            .col = start_col,
        };
    }

    fn readPunctuation(self: *Lexer, start_line: u32, start_col: u32) Token {
        const start = self.cursor;
        const c1 = self.advance();

        var tt: TokenType = .Eof;
        switch (c1) {
            '(' => tt = .LParen,
            ')' => tt = .RParen,
            '{' => tt = .LBrace,
            '}' => tt = .RBrace,
            '[' => tt = .LBracket,
            ']' => tt = .RBracket,
            ';' => tt = .Semicolon,
            ',' => tt = .Comma,
            ':' => tt = .Colon,
            '+' => tt = .Plus,
            '-' => tt = .Minus,
            '*' => tt = .Star,
            '/' => tt = .Slash,
            '%' => tt = .Percent,
            '?' => {
                if (self.peek() == '?') {
                    _ = self.advance();
                    tt = .QuestionQuestion;
                } else {
                    tt = .Question;
                }
            },
            '.' => {
                if (self.peek() == '.' and self.cursor + 1 < self.source.len and self.source[self.cursor + 1] == '.') {
                    _ = self.advance();
                    _ = self.advance();
                    tt = .Spread;
                } else {
                    tt = .Dot;
                }
            },
            '=' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    if (self.peek() == '=') {
                        _ = self.advance();
                        tt = .EqualEqualEqual;
                    } else {
                        tt = .EqualEqual;
                    }
                } else if (self.peek() == '>') {
                    _ = self.advance();
                    tt = .Arrow;
                } else {
                    tt = .Equal;
                }
            },
            '!' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    if (self.peek() == '=') {
                        _ = self.advance();
                        tt = .BangEqualEqual;
                    } else {
                        tt = .BangEqual;
                    }
                } else {
                    tt = .Bang;
                }
            },
            '<' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    tt = .LessEqual;
                } else {
                    tt = .Less;
                }
            },
            '>' => {
                if (self.peek() == '=') {
                    _ = self.advance();
                    tt = .GreaterEqual;
                } else {
                    tt = .Greater;
                }
            },
            '&' => {
                if (self.peek() == '&') {
                    _ = self.advance();
                    tt = .AmpersandAmpersand;
                }
            },
            '|' => {
                if (self.peek() == '|') {
                    _ = self.advance();
                    tt = .PipePipe;
                }
            },
            else => {},
        }

        return Token{
            .token_type = tt,
            .lexeme = self.source[start..self.cursor],
            .line = start_line,
            .col = start_col,
        };
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_' or c == '$';
    }

    fn isIdentPart(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
    }

    fn matchKeyword(s: []const u8) TokenType {
        if (std.mem.eql(u8, s, "let")) return .KwLet;
        if (std.mem.eql(u8, s, "const")) return .KwConst;
        if (std.mem.eql(u8, s, "var")) return .KwVar;
        if (std.mem.eql(u8, s, "function")) return .KwFunction;
        if (std.mem.eql(u8, s, "return")) return .KwReturn;
        if (std.mem.eql(u8, s, "if")) return .KwIf;
        if (std.mem.eql(u8, s, "else")) return .KwElse;
        if (std.mem.eql(u8, s, "while")) return .KwWhile;
        if (std.mem.eql(u8, s, "for")) return .KwFor;
        if (std.mem.eql(u8, s, "break")) return .KwBreak;
        if (std.mem.eql(u8, s, "continue")) return .KwContinue;
        if (std.mem.eql(u8, s, "new")) return .KwNew;
        if (std.mem.eql(u8, s, "this")) return .KwThis;
        if (std.mem.eql(u8, s, "typeof")) return .KwTypeof;
        if (std.mem.eql(u8, s, "instanceof")) return .KwInstanceof;
        if (std.mem.eql(u8, s, "try")) return .KwTry;
        if (std.mem.eql(u8, s, "catch")) return .KwCatch;
        if (std.mem.eql(u8, s, "finally")) return .KwFinally;
        if (std.mem.eql(u8, s, "throw")) return .KwThrow;
        if (std.mem.eql(u8, s, "class")) return .KwClass;
        if (std.mem.eql(u8, s, "async")) return .KwAsync;
        if (std.mem.eql(u8, s, "await")) return .KwAwait;
        if (std.mem.eql(u8, s, "import")) return .KwImport;
        if (std.mem.eql(u8, s, "export")) return .KwExport;
        if (std.mem.eql(u8, s, "default")) return .KwDefault;
        if (std.mem.eql(u8, s, "true")) return .KwTrue;
        if (std.mem.eql(u8, s, "false")) return .KwFalse;
        if (std.mem.eql(u8, s, "null")) return .KwNull;
        if (std.mem.eql(u8, s, "undefined")) return .KwUndefined;
        return .Identifier;
    }
};

test "lexer tokenize javascript" {
    const src =
        \\function add(a, b) {
        \\    let sum = a + b;
        \\    return sum;
        \\}
    ;
    var lexer = Lexer.init(src);
    try std.testing.expectEqual(TokenType.KwFunction, lexer.nextToken().token_type);
    const tok_ident = lexer.nextToken();
    try std.testing.expectEqual(TokenType.Identifier, tok_ident.token_type);
    try std.testing.expectEqualStrings("add", tok_ident.lexeme);
    try std.testing.expectEqual(TokenType.LParen, lexer.nextToken().token_type);
}
