//! WHATWG HTML5 compliant streaming tokenizer state machine.
const std = @import("std");

pub const HTMLTokenType = enum {
    DOCTYPE,
    StartTag,
    EndTag,
    Comment,
    Character,
    EOF,
};

pub const HTMLAttribute = struct {
    name: []const u8,
    value: []const u8,
};

pub const HTMLToken = struct {
    token_type: HTMLTokenType,
    data: []const u8 = "",
    attributes: std.ArrayList(HTMLAttribute),
    self_closing: bool = false,

    pub fn init(token_type: HTMLTokenType) HTMLToken {
        return .{
            .token_type = token_type,
            .data = "",
            .attributes = .empty,
            .self_closing = false,
        };
    }

    pub fn deinit(self: *HTMLToken, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
    }
};

pub const HTMLState = enum {
    Data,
    TagOpen,
    EndTagOpen,
    TagName,
    BeforeAttributeName,
    AttributeName,
    AfterAttributeName,
    BeforeAttributeValue,
    AttributeValueDoubleQuoted,
    AttributeValueSingleQuoted,
    AttributeValueUnquoted,
    AfterAttributeValueQuoted,
    SelfClosingStartTag,
    CommentStart,
    Comment,
    CommentEnd,
    MarkupDeclarationOpen,
    DOCTYPE,
};

pub const HTMLTokenizer = struct {
    source: []const u8,
    cursor: usize = 0,
    state: HTMLState = .Data,

    pub fn init(source: []const u8) HTMLTokenizer {
        return .{
            .source = source,
            .cursor = 0,
            .state = .Data,
        };
    }

    pub fn nextToken(self: *HTMLTokenizer, allocator: std.mem.Allocator) !HTMLToken {
        var token = HTMLToken.init(.Character);
        errdefer token.deinit(allocator);

        while (self.cursor < self.source.len) {
            const ch = self.source[self.cursor];

            switch (self.state) {
                .Data => {
                    if (ch == '<') {
                        self.cursor += 1;
                        self.state = .TagOpen;
                    } else {
                        const start = self.cursor;
                        while (self.cursor < self.source.len and self.source[self.cursor] != '<') {
                            self.cursor += 1;
                        }
                        token.token_type = .Character;
                        token.data = self.source[start..self.cursor];
                        return token;
                    }
                },
                .TagOpen => {
                    if (ch == '/') {
                        self.cursor += 1;
                        self.state = .EndTagOpen;
                    } else if (std.ascii.isAlphabetic(ch)) {
                        self.state = .TagName;
                        token.token_type = .StartTag;
                    } else if (ch == '!') {
                        self.cursor += 1;
                        self.state = .MarkupDeclarationOpen;
                    } else {
                        self.state = .Data;
                    }
                },
                .EndTagOpen => {
                    if (std.ascii.isAlphabetic(ch)) {
                        self.state = .TagName;
                        token.token_type = .EndTag;
                    } else {
                        self.state = .Data;
                    }
                },
                .TagName => {
                    const start = self.cursor;
                    while (self.cursor < self.source.len) {
                        const c = self.source[self.cursor];
                        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                            token.data = self.source[start..self.cursor];
                            self.cursor += 1;
                            self.state = .BeforeAttributeName;
                            break;
                        } else if (c == '/') {
                            token.data = self.source[start..self.cursor];
                            self.cursor += 1;
                            self.state = .SelfClosingStartTag;
                            break;
                        } else if (c == '>') {
                            token.data = self.source[start..self.cursor];
                            self.cursor += 1;
                            self.state = .Data;
                            return token;
                        }
                        self.cursor += 1;
                    }
                    if (self.state == .TagName) {
                        token.data = self.source[start..self.cursor];
                        self.state = .Data;
                        return token;
                    }
                },
                .BeforeAttributeName => {
                    if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
                        self.cursor += 1;
                    } else if (ch == '/') {
                        self.cursor += 1;
                        self.state = .SelfClosingStartTag;
                    } else if (ch == '>') {
                        self.cursor += 1;
                        self.state = .Data;
                        return token;
                    } else {
                        self.state = .AttributeName;
                    }
                },
                .AttributeName => {
                    const start = self.cursor;
                    while (self.cursor < self.source.len) {
                        const c = self.source[self.cursor];
                        if (c == '=' or c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '/' or c == '>') {
                            break;
                        }
                        self.cursor += 1;
                    }
                    const attr_name = self.source[start..self.cursor];
                    var attr_val: []const u8 = "";

                    // Check for '='
                    while (self.cursor < self.source.len and (self.source[self.cursor] == ' ' or self.source[self.cursor] == '\t')) {
                        self.cursor += 1;
                    }

                    if (self.cursor < self.source.len and self.source[self.cursor] == '=') {
                        self.cursor += 1;
                        while (self.cursor < self.source.len and (self.source[self.cursor] == ' ' or self.source[self.cursor] == '\t')) {
                            self.cursor += 1;
                        }
                        if (self.cursor < self.source.len) {
                            const q = self.source[self.cursor];
                            if (q == '"' or q == '\'') {
                                self.cursor += 1;
                                const val_start = self.cursor;
                                while (self.cursor < self.source.len and self.source[self.cursor] != q) {
                                    self.cursor += 1;
                                }
                                attr_val = self.source[val_start..self.cursor];
                                if (self.cursor < self.source.len) self.cursor += 1;
                            } else {
                                const val_start = self.cursor;
                                while (self.cursor < self.source.len and self.source[self.cursor] != ' ' and self.source[self.cursor] != '>') {
                                    self.cursor += 1;
                                }
                                attr_val = self.source[val_start..self.cursor];
                            }
                        }
                    }

                    try token.attributes.append(allocator, .{ .name = attr_name, .value = attr_val });
                    self.state = .BeforeAttributeName;
                },
                .SelfClosingStartTag => {
                    if (ch == '>') {
                        self.cursor += 1;
                        token.self_closing = true;
                        self.state = .Data;
                        return token;
                    }
                    self.state = .BeforeAttributeName;
                },
                .MarkupDeclarationOpen => {
                    if (std.mem.startsWith(u8, self.source[self.cursor..], "--")) {
                        self.cursor += 2;
                        self.state = .Comment;
                    } else if (self.source.len >= self.cursor + 7 and std.ascii.eqlIgnoreCase(self.source[self.cursor .. self.cursor + 7], "doctype")) {
                        self.cursor += 7;
                        self.state = .DOCTYPE;
                    } else {
                        self.state = .Data;
                    }
                },
                .Comment => {
                    const start = self.cursor;
                    while (self.cursor + 2 < self.source.len) {
                        if (std.mem.startsWith(u8, self.source[self.cursor..], "-->")) {
                            token.token_type = .Comment;
                            token.data = self.source[start..self.cursor];
                            self.cursor += 3;
                            self.state = .Data;
                            return token;
                        }
                        self.cursor += 1;
                    }
                    token.token_type = .Comment;
                    token.data = self.source[start..self.source.len];
                    self.cursor = self.source.len;
                    self.state = .Data;
                    return token;
                },
                .DOCTYPE => {
                    while (self.cursor < self.source.len and self.source[self.cursor] != '>') {
                        self.cursor += 1;
                    }
                    if (self.cursor < self.source.len) self.cursor += 1;
                    token.token_type = .DOCTYPE;
                    self.state = .Data;
                    return token;
                },
                else => {
                    self.cursor += 1;
                },
            }
        }

        token.token_type = .EOF;
        return token;
    }
};

test "html streaming tokenizer" {
    const allocator = std.testing.allocator;
    const html = "<!DOCTYPE html><div class=\"container\"><p>Hello Davoth</p></div>";
    var tokenizer = HTMLTokenizer.init(html);

    var tok = try tokenizer.nextToken(allocator);
    defer tok.deinit(allocator);
    try std.testing.expectEqual(HTMLTokenType.DOCTYPE, tok.token_type);

    var tok2 = try tokenizer.nextToken(allocator);
    defer tok2.deinit(allocator);
    try std.testing.expectEqual(HTMLTokenType.StartTag, tok2.token_type);
    try std.testing.expectEqualStrings("div", tok2.data);
    try std.testing.expectEqual(@as(usize, 1), tok2.attributes.items.len);
    try std.testing.expectEqualStrings("class", tok2.attributes.items[0].name);
    try std.testing.expectEqualStrings("container", tok2.attributes.items[0].value);
}
