//! Recursive descent & Pratt expression parser for ECMAScript.
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const Node = @import("ast.zig").Node;
const BinaryOperator = @import("ast.zig").BinaryOperator;
const UnaryOperator = @import("ast.zig").UnaryOperator;

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    current: Token,
    previous: Token,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var p = Parser{
            .allocator = allocator,
            .lexer = Lexer.init(source),
            .current = undefined,
            .previous = undefined,
        };
        p.advance();
        return p;
    }

    fn advance(self: *Parser) void {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
    }

    fn match(self: *Parser, tt: TokenType) bool {
        if (self.current.token_type == tt) {
            self.advance();
            return true;
        }
        return false;
    }

    fn consume(self: *Parser, tt: TokenType, err_msg: []const u8) !void {
        if (self.current.token_type == tt) {
            self.advance();
            return;
        }
        _ = err_msg;
        return error.UnexpectedToken;
    }

    pub fn parseProgram(self: *Parser) !*Node {
        var statements: std.ArrayList(*Node) = .empty;
        errdefer statements.deinit(self.allocator);

        while (self.current.token_type != .Eof) {
            const stmt = try self.parseDeclarationOrStatement();
            try statements.append(self.allocator, stmt);
        }

        const prog_node = try self.allocator.create(Node);
        prog_node.* = .{
            .data = .{
                .Program = try statements.toOwnedSlice(self.allocator),
            },
        };
        return prog_node;
    }

    fn parseDeclarationOrStatement(self: *Parser) anyerror!*Node {
        if (self.match(.KwFunction)) {
            return self.parseFunctionDecl(false);
        }
        if (self.match(.KwAsync)) {
            if (self.match(.KwFunction)) {
                return self.parseFunctionDecl(true);
            }
        }
        if (self.match(.KwLet) or self.match(.KwConst) or self.match(.KwVar)) {
            return self.parseVarDecl();
        }
        if (self.match(.KwIf)) {
            return self.parseIfStatement();
        }
        if (self.match(.KwWhile)) {
            return self.parseWhileStatement();
        }
        if (self.match(.KwFor)) {
            return self.parseForStatement();
        }
        if (self.match(.KwReturn)) {
            return self.parseReturnStatement();
        }
        if (self.match(.KwThrow)) {
            return self.parseThrowStatement();
        }
        if (self.match(.KwTry)) {
            return self.parseTryCatchStatement();
        }
        if (self.match(.LBrace)) {
            return self.parseBlock();
        }

        // Expression statement
        const expr = try self.parseExpression();
        _ = self.match(.Semicolon);
        const node = try self.allocator.create(Node);
        node.* = .{ .data = .{ .ExprStatement = expr } };
        return node;
    }

    fn parseVarDecl(self: *Parser) anyerror!*Node {
        const is_const = (self.previous.token_type == .KwConst);
        const name = self.current.lexeme;
        try self.consume(.Identifier, "Expected variable name");

        var init_expr: ?*Node = null;
        if (self.match(.Equal)) {
            init_expr = try self.parseExpression();
        }
        _ = self.match(.Semicolon);

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .VarDecl = .{
                    .name = name,
                    .init = init_expr,
                    .is_const = is_const,
                },
            },
        };
        return node;
    }

    fn parseFunctionDecl(self: *Parser, is_async: bool) anyerror!*Node {
        const name = self.current.lexeme;
        try self.consume(.Identifier, "Expected function name");
        try self.consume(.LParen, "Expected '(' after function name");

        var params: std.ArrayList([]const u8) = .empty;
        errdefer params.deinit(self.allocator);

        if (self.current.token_type != .RParen) {
            while (true) {
                const param_name = self.current.lexeme;
                try self.consume(.Identifier, "Expected parameter name");
                try params.append(self.allocator, param_name);
                if (!self.match(.Comma)) break;
            }
        }
        try self.consume(.RParen, "Expected ')' after parameters");
        try self.consume(.LBrace, "Expected '{' before function body");

        const body = try self.parseBlock();

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .FunctionDecl = .{
                    .name = name,
                    .params = try params.toOwnedSlice(self.allocator),
                    .body = body,
                    .is_async = is_async,
                },
            },
        };
        return node;
    }

    fn parseBlock(self: *Parser) anyerror!*Node {
        var stmts: std.ArrayList(*Node) = .empty;
        errdefer stmts.deinit(self.allocator);

        while (self.current.token_type != .RBrace and self.current.token_type != .Eof) {
            const stmt = try self.parseDeclarationOrStatement();
            try stmts.append(self.allocator, stmt);
        }
        try self.consume(.RBrace, "Expected '}'");

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .Block = try stmts.toOwnedSlice(self.allocator),
            },
        };
        return node;
    }

    fn parseIfStatement(self: *Parser) anyerror!*Node {
        try self.consume(.LParen, "Expected '('");
        const cond = try self.parseExpression();
        try self.consume(.RParen, "Expected ')'");

        const consequent = try self.parseDeclarationOrStatement();
        var alternate: ?*Node = null;
        if (self.match(.KwElse)) {
            alternate = try self.parseDeclarationOrStatement();
        }

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .If = .{
                    .condition = cond,
                    .consequent = consequent,
                    .alternate = alternate,
                },
            },
        };
        return node;
    }

    fn parseWhileStatement(self: *Parser) anyerror!*Node {
        try self.consume(.LParen, "Expected '('");
        const cond = try self.parseExpression();
        try self.consume(.RParen, "Expected ')'");
        const body = try self.parseDeclarationOrStatement();

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .While = .{
                    .condition = cond,
                    .body = body,
                },
            },
        };
        return node;
    }

    fn parseForStatement(self: *Parser) anyerror!*Node {
        try self.consume(.LParen, "Expected '('");
        var init_node: ?*Node = null;
        if (!self.match(.Semicolon)) {
            if (self.match(.KwLet) or self.match(.KwVar)) {
                init_node = try self.parseVarDecl();
            } else {
                init_node = try self.parseExpression();
                try self.consume(.Semicolon, "Expected ';'");
            }
        }

        var cond_node: ?*Node = null;
        if (self.current.token_type != .Semicolon) {
            cond_node = try self.parseExpression();
        }
        try self.consume(.Semicolon, "Expected ';'");

        var update_node: ?*Node = null;
        if (self.current.token_type != .RParen) {
            update_node = try self.parseExpression();
        }
        try self.consume(.RParen, "Expected ')'");

        const body = try self.parseDeclarationOrStatement();

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .For = .{
                    .init = init_node,
                    .condition = cond_node,
                    .update = update_node,
                    .body = body,
                },
            },
        };
        return node;
    }

    fn parseReturnStatement(self: *Parser) anyerror!*Node {
        var value: ?*Node = null;
        if (self.current.token_type != .Semicolon and self.current.token_type != .RBrace) {
            value = try self.parseExpression();
        }
        _ = self.match(.Semicolon);

        const node = try self.allocator.create(Node);
        node.* = .{ .data = .{ .Return = value } };
        return node;
    }

    fn parseThrowStatement(self: *Parser) anyerror!*Node {
        const expr = try self.parseExpression();
        _ = self.match(.Semicolon);

        const node = try self.allocator.create(Node);
        node.* = .{ .data = .{ .Throw = expr } };
        return node;
    }

    fn parseTryCatchStatement(self: *Parser) anyerror!*Node {
        try self.consume(.LBrace, "Expected '{'");
        const try_blk = try self.parseBlock();

        var catch_param: ?[]const u8 = null;
        var catch_blk: ?*Node = null;

        if (self.match(.KwCatch)) {
            if (self.match(.LParen)) {
                catch_param = self.current.lexeme;
                try self.consume(.Identifier, "Expected identifier");
                try self.consume(.RParen, "Expected ')'");
            }
            try self.consume(.LBrace, "Expected '{'");
            catch_blk = try self.parseBlock();
        }

        var fin_blk: ?*Node = null;
        if (self.match(.KwFinally)) {
            try self.consume(.LBrace, "Expected '{'");
            fin_blk = try self.parseBlock();
        }

        const node = try self.allocator.create(Node);
        node.* = .{
            .data = .{
                .TryCatch = .{
                    .try_block = try_blk,
                    .catch_param = catch_param,
                    .catch_block = catch_blk,
                    .finally_block = fin_blk,
                },
            },
        };
        return node;
    }

    pub fn parseExpression(self: *Parser) anyerror!*Node {
        return self.parseAssignment();
    }

    fn parseAssignment(self: *Parser) anyerror!*Node {
        const left = try self.parseLogicalOr();

        if (self.match(.Equal)) {
            const right = try self.parseAssignment();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Assignment = .{
                        .target = left,
                        .value = right,
                    },
                },
            };
            return node;
        }

        return left;
    }

    fn parseLogicalOr(self: *Parser) anyerror!*Node {
        var left = try self.parseLogicalAnd();
        while (self.match(.PipePipe)) {
            const right = try self.parseLogicalAnd();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = .LogicalOr,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseLogicalAnd(self: *Parser) anyerror!*Node {
        var left = try self.parseEquality();
        while (self.match(.AmpersandAmpersand)) {
            const right = try self.parseEquality();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = .LogicalAnd,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseEquality(self: *Parser) anyerror!*Node {
        var left = try self.parseRelational();
        while (true) {
            var op: ?BinaryOperator = null;
            if (self.match(.EqualEqualEqual)) {
                op = .StrictEqual;
            } else if (self.match(.EqualEqual)) {
                op = .Equal;
            } else if (self.match(.BangEqualEqual)) {
                op = .StrictNotEqual;
            } else if (self.match(.BangEqual)) {
                op = .NotEqual;
            } else {
                break;
            }

            const right = try self.parseRelational();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = op.?,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseRelational(self: *Parser) anyerror!*Node {
        var left = try self.parseAdditive();
        while (true) {
            var op: ?BinaryOperator = null;
            if (self.match(.Less)) {
                op = .Less;
            } else if (self.match(.LessEqual)) {
                op = .LessEqual;
            } else if (self.match(.Greater)) {
                op = .Greater;
            } else if (self.match(.GreaterEqual)) {
                op = .GreaterEqual;
            } else {
                break;
            }

            const right = try self.parseAdditive();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = op.?,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseAdditive(self: *Parser) anyerror!*Node {
        var left = try self.parseMultiplicative();
        while (true) {
            var op: ?BinaryOperator = null;
            if (self.match(.Plus)) {
                op = .Add;
            } else if (self.match(.Minus)) {
                op = .Sub;
            } else {
                break;
            }

            const right = try self.parseMultiplicative();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = op.?,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseMultiplicative(self: *Parser) anyerror!*Node {
        var left = try self.parseUnary();
        while (true) {
            var op: ?BinaryOperator = null;
            if (self.match(.Star)) {
                op = .Mul;
            } else if (self.match(.Slash)) {
                op = .Div;
            } else if (self.match(.Percent)) {
                op = .Mod;
            } else {
                break;
            }

            const right = try self.parseUnary();
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = .{
                    .Binary = .{
                        .op = op.?,
                        .left = left,
                        .right = right,
                    },
                },
            };
            left = node;
        }
        return left;
    }

    fn parseUnary(self: *Parser) anyerror!*Node {
        if (self.match(.Bang)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .Unary = .{ .op = .Not, .expr = expr } } };
            return node;
        }
        if (self.match(.Minus)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .Unary = .{ .op = .Negate, .expr = expr } } };
            return node;
        }
        if (self.match(.KwAwait)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .Await = expr } };
            return node;
        }
        return self.parseCallOrMember();
    }

    fn parseCallOrMember(self: *Parser) anyerror!*Node {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.LParen)) {
                var args: std.ArrayList(*Node) = .empty;
                errdefer args.deinit(self.allocator);
                if (self.current.token_type != .RParen) {
                    while (true) {
                        const arg = try self.parseExpression();
                        try args.append(self.allocator, arg);
                        if (!self.match(.Comma)) break;
                    }
                }
                try self.consume(.RParen, "Expected ')' after arguments");

                const call_node = try self.allocator.create(Node);
                call_node.* = .{
                    .data = .{
                        .Call = .{
                            .callee = expr,
                            .arguments = try args.toOwnedSlice(self.allocator),
                        },
                    },
                };
                expr = call_node;
            } else if (self.match(.Dot)) {
                const prop_name = self.current.lexeme;
                try self.consume(.Identifier, "Expected property name after '.'");
                const member_node = try self.allocator.create(Node);
                member_node.* = .{
                    .data = .{
                        .Member = .{
                            .object = expr,
                            .property = prop_name,
                            .computed = false,
                        },
                    },
                };
                expr = member_node;
            } else {
                break;
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) anyerror!*Node {
        if (self.match(.Number)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .NumberLiteral = self.previous.num_value } };
            return node;
        }
        if (self.match(.String)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .StringLiteral = self.previous.lexeme } };
            return node;
        }
        if (self.match(.KwTrue)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .BooleanLiteral = true } };
            return node;
        }
        if (self.match(.KwFalse)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .BooleanLiteral = false } };
            return node;
        }
        if (self.match(.KwNull)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .NullLiteral = {} } };
            return node;
        }
        if (self.match(.KwUndefined)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .UndefinedLiteral = {} } };
            return node;
        }
        if (self.match(.Identifier)) {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = .{ .Identifier = self.previous.lexeme } };
            return node;
        }
        if (self.match(.LParen)) {
            const expr = try self.parseExpression();
            try self.consume(.RParen, "Expected ')'");
            return expr;
        }

        return error.UnexpectedToken;
    }
};

test "parser basic function and arithmetic" {
    const allocator = std.testing.allocator;
    const src = "function add(a, b) { return a + b * 2; }";
    var parser = Parser.init(allocator, src);
    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    try std.testing.expect(ast.data == .Program);
    try std.testing.expectEqual(@as(usize, 1), ast.data.Program.len);
    try std.testing.expect(ast.data.Program[0].data == .FunctionDecl);
}
