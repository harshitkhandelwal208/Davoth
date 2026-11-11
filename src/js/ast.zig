//! Abstract Syntax Tree node definitions for ECMAScript.
const std = @import("std");

pub const BinaryOperator = enum {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Equal,
    StrictEqual,
    NotEqual,
    StrictNotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    LogicalAnd,
    LogicalOr,
    NullishCoalesce,
};

pub const UnaryOperator = enum {
    Not,
    Negate,
    Typeof,
};

pub const Node = struct {
    data: NodeData,

    pub const NodeData = union(enum) {
        // Expressions
        NumberLiteral: f64,
        StringLiteral: []const u8,
        BooleanLiteral: bool,
        NullLiteral: void,
        UndefinedLiteral: void,
        Identifier: []const u8,
        Binary: struct {
            op: BinaryOperator,
            left: *Node,
            right: *Node,
        },
        Unary: struct {
            op: UnaryOperator,
            expr: *Node,
        },
        Assignment: struct {
            target: *Node,
            value: *Node,
        },
        Call: struct {
            callee: *Node,
            arguments: []*Node,
        },
        Member: struct {
            object: *Node,
            property: []const u8,
            computed: bool,
        },
        ArrayLiteral: []*Node,
        ObjectLiteral: []struct {
            key: []const u8,
            value: *Node,
        },
        ArrowFunction: struct {
            params: [][]const u8,
            body: *Node,
            is_async: bool,
        },
        Await: *Node,

        // Statements
        ExprStatement: *Node,
        VarDecl: struct {
            name: []const u8,
            init: ?*Node,
            is_const: bool,
        },
        Block: []*Node,
        If: struct {
            condition: *Node,
            consequent: *Node,
            alternate: ?*Node,
        },
        While: struct {
            condition: *Node,
            body: *Node,
        },
        For: struct {
            init: ?*Node,
            condition: ?*Node,
            update: ?*Node,
            body: *Node,
        },
        Return: ?*Node,
        Throw: *Node,
        TryCatch: struct {
            try_block: *Node,
            catch_param: ?[]const u8,
            catch_block: ?*Node,
            finally_block: ?*Node,
        },
        FunctionDecl: struct {
            name: []const u8,
            params: [][]const u8,
            body: *Node,
            is_async: bool,
        },
        Program: []*Node,
    };

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .Binary => |b| {
                b.left.deinit(allocator);
                b.right.deinit(allocator);
            },
            .Unary => |u| {
                u.expr.deinit(allocator);
            },
            .Assignment => |a| {
                a.target.deinit(allocator);
                a.value.deinit(allocator);
            },
            .Call => |c| {
                c.callee.deinit(allocator);
                for (c.arguments) |arg| arg.deinit(allocator);
                allocator.free(c.arguments);
            },
            .Member => |m| {
                m.object.deinit(allocator);
            },
            .ArrayLiteral => |arr| {
                for (arr) |item| item.deinit(allocator);
                allocator.free(arr);
            },
            .ObjectLiteral => |props| {
                for (props) |p| p.value.deinit(allocator);
                allocator.free(props);
            },
            .ArrowFunction => |f| {
                f.body.deinit(allocator);
                allocator.free(f.params);
            },
            .Await => |w| w.deinit(allocator),
            .ExprStatement => |e| e.deinit(allocator),
            .VarDecl => |v| {
                if (v.init) |i| i.deinit(allocator);
            },
            .Block => |stmts| {
                for (stmts) |s| s.deinit(allocator);
                allocator.free(stmts);
            },
            .If => |i| {
                i.condition.deinit(allocator);
                i.consequent.deinit(allocator);
                if (i.alternate) |a| a.deinit(allocator);
            },
            .While => |w| {
                w.condition.deinit(allocator);
                w.body.deinit(allocator);
            },
            .For => |f| {
                if (f.init) |init| init.deinit(allocator);
                if (f.condition) |cond| cond.deinit(allocator);
                if (f.update) |up| up.deinit(allocator);
                f.body.deinit(allocator);
            },
            .Return => |r| {
                if (r) |val| val.deinit(allocator);
            },
            .Throw => |t| t.deinit(allocator),
            .TryCatch => |tc| {
                tc.try_block.deinit(allocator);
                if (tc.catch_block) |cb| cb.deinit(allocator);
                if (tc.finally_block) |fb| fb.deinit(allocator);
            },
            .FunctionDecl => |fd| {
                fd.body.deinit(allocator);
                allocator.free(fd.params);
            },
            .Program => |prog| {
                for (prog) |stmt| stmt.deinit(allocator);
                allocator.free(prog);
            },
            else => {},
        }
        allocator.destroy(self);
    }
};
