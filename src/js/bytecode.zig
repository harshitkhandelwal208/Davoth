//! Bytecode instruction set and AST-to-bytecode compiler.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const Node = @import("ast.zig").Node;
const BinaryOperator = @import("ast.zig").BinaryOperator;

pub const OpCode = enum(u8) {
    LoadConst = 1,
    LoadLocal = 2,
    StoreLocal = 3,
    LoadGlobal = 4,
    StoreGlobal = 5,
    GetProp = 6,
    SetProp = 7,
    Add = 8,
    Sub = 9,
    Mul = 10,
    Div = 11,
    Mod = 12,
    Equal = 13,
    StrictEqual = 14,
    NotEqual = 15,
    StrictNotEqual = 16,
    Less = 17,
    LessEqual = 18,
    Greater = 19,
    GreaterEqual = 20,
    Not = 21,
    Negate = 22,
    Jump = 23,
    JumpIfFalse = 24,
    Call = 25,
    Return = 26,
    Pop = 27,
    Dup = 28,
    Await = 29,
    Throw = 30,
    CreateFunction = 31,
    CreateObject = 32,
    CreateArray = 33,
    LogicalAnd = 34,
    LogicalOr = 35,
};

pub const CodeBlock = struct {
    allocator: std.mem.Allocator,
    instructions: std.ArrayList(u8),
    constants: std.ArrayList(JSValue),
    local_names: std.ArrayList([]const u8),
    functions: std.ArrayList(*CodeBlock) = .empty,
    name: []const u8 = "main",

    pub fn init(allocator: std.mem.Allocator, name: []const u8) CodeBlock {
        return .{
            .allocator = allocator,
            .instructions = .empty,
            .constants = .empty,
            .local_names = .empty,
            .functions = .empty,
            .name = name,
        };
    }

    pub fn deinit(self: *CodeBlock) void {
        for (self.functions.items) |f| {
            f.deinit();
            self.allocator.destroy(f);
        }
        self.functions.deinit(self.allocator);
        self.instructions.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.local_names.deinit(self.allocator);
    }

    pub fn emitOp(self: *CodeBlock, op: OpCode) !void {
        try self.instructions.append(self.allocator, @intFromEnum(op));
    }

    pub fn emitU16(self: *CodeBlock, val: u16) !void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, val, .little);
        try self.instructions.appendSlice(self.allocator, &bytes);
    }

    pub fn emitI32(self: *CodeBlock, val: i32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, val, .little);
        try self.instructions.appendSlice(self.allocator, &bytes);
    }

    pub fn addConstant(self: *CodeBlock, val: JSValue) !u16 {
        const idx: u16 = @truncate(self.constants.items.len);
        try self.constants.append(self.allocator, val);
        return idx;
    }

    pub fn resolveOrAddLocal(self: *CodeBlock, name: []const u8) !u16 {
        for (self.local_names.items, 0..) |loc, i| {
            if (std.mem.eql(u8, loc, name)) return @truncate(i);
        }
        const idx: u16 = @truncate(self.local_names.items.len);
        try self.local_names.append(self.allocator, name);
        return idx;
    }

    pub fn addLocal(self: *CodeBlock, name: []const u8) !u16 {
        return self.resolveOrAddLocal(name);
    }

    pub fn resolveLocal(self: *CodeBlock, name: []const u8) ?u16 {
        for (self.local_names.items, 0..) |loc, i| {
            if (std.mem.eql(u8, loc, name)) return @truncate(i);
        }
        return null;
    }
};

pub const BytecodeCompiler = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    code: CodeBlock,

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable, name: []const u8) BytecodeCompiler {
        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .code = CodeBlock.init(allocator, name),
        };
    }

    pub fn compile(self: *BytecodeCompiler, ast: *Node) !CodeBlock {
        try self.compileNode(ast);
        try self.code.emitOp(.Return);
        return self.code;
    }

    fn compileNode(self: *BytecodeCompiler, node: *Node) anyerror!void {
        switch (node.data) {
            .Program => |stmts| {
                for (stmts, 0..) |stmt, i| {
                    const is_last = (i == stmts.len - 1);
                    if (is_last and stmt.data == .ExprStatement) {
                        try self.compileNode(stmt.data.ExprStatement);
                    } else {
                        try self.compileNode(stmt);
                    }
                }
            },
            .NumberLiteral => |num| {
                const c_idx = try self.code.addConstant(JSValue.fromFloat64(num));
                try self.code.emitOp(.LoadConst);
                try self.code.emitU16(c_idx);
            },
            .StringLiteral => |str| {
                const atom = try self.atom_table.intern(str);
                const c_idx = try self.code.addConstant(JSValue.fromStringAtom(atom));
                try self.code.emitOp(.LoadConst);
                try self.code.emitU16(c_idx);
            },
            .BooleanLiteral => |b| {
                const c_idx = try self.code.addConstant(JSValue.fromBoolean(b));
                try self.code.emitOp(.LoadConst);
                try self.code.emitU16(c_idx);
            },
            .NullLiteral => {
                const c_idx = try self.code.addConstant(JSValue.null_val);
                try self.code.emitOp(.LoadConst);
                try self.code.emitU16(c_idx);
            },
            .UndefinedLiteral => {
                const c_idx = try self.code.addConstant(JSValue.undefined_val);
                try self.code.emitOp(.LoadConst);
                try self.code.emitU16(c_idx);
            },
            .Identifier => |name| {
                if (self.code.resolveLocal(name)) |slot| {
                    try self.code.emitOp(.LoadLocal);
                    try self.code.emitU16(slot);
                } else {
                    const atom = try self.atom_table.intern(name);
                    try self.code.emitOp(.LoadGlobal);
                    try self.code.emitU16(@truncate(atom.toU32()));
                }
            },
            .VarDecl => |v| {
                const slot = try self.code.resolveOrAddLocal(v.name);
                if (v.init) |init_node| {
                    try self.compileNode(init_node);
                } else {
                    const c_idx = try self.code.addConstant(JSValue.undefined_val);
                    try self.code.emitOp(.LoadConst);
                    try self.code.emitU16(c_idx);
                }
                try self.code.emitOp(.StoreLocal);
                try self.code.emitU16(slot);
            },
            .ExprStatement => |expr| {
                try self.compileNode(expr);
                try self.code.emitOp(.Pop);
            },
            .Binary => |b| {
                try self.compileNode(b.left);
                try self.compileNode(b.right);
                switch (b.op) {
                    .Add => try self.code.emitOp(.Add),
                    .Sub => try self.code.emitOp(.Sub),
                    .Mul => try self.code.emitOp(.Mul),
                    .Div => try self.code.emitOp(.Div),
                    .Mod => try self.code.emitOp(.Mod),
                    .Equal => try self.code.emitOp(.Equal),
                    .StrictEqual => try self.code.emitOp(.StrictEqual),
                    .NotEqual => try self.code.emitOp(.NotEqual),
                    .StrictNotEqual => try self.code.emitOp(.StrictNotEqual),
                    .Less => try self.code.emitOp(.Less),
                    .LessEqual => try self.code.emitOp(.LessEqual),
                    .Greater => try self.code.emitOp(.Greater),
                    .GreaterEqual => try self.code.emitOp(.GreaterEqual),
                    .LogicalAnd => try self.code.emitOp(.LogicalAnd),
                    .LogicalOr => try self.code.emitOp(.LogicalOr),
                    else => try self.code.emitOp(.Add),
                }
            },
            .Unary => |u| {
                try self.compileNode(u.expr);
                switch (u.op) {
                    .Not => try self.code.emitOp(.Not),
                    .Negate => try self.code.emitOp(.Negate),
                    .Typeof => {},
                }
            },
            .Assignment => |a| {
                try self.compileNode(a.value);
                if (a.target.data == .Identifier) {
                    const name = a.target.data.Identifier;
                    if (self.code.resolveLocal(name)) |slot| {
                        try self.code.emitOp(.Dup);
                        try self.code.emitOp(.StoreLocal);
                        try self.code.emitU16(slot);
                    } else {
                        const atom = try self.atom_table.intern(name);
                        try self.code.emitOp(.Dup);
                        try self.code.emitOp(.StoreGlobal);
                        try self.code.emitU16(@truncate(atom.toU32()));
                    }
                }
            },
            .Call => |c| {
                for (c.arguments) |arg| {
                    try self.compileNode(arg);
                }
                try self.compileNode(c.callee);
                try self.code.emitOp(.Call);
                try self.code.instructions.append(self.allocator, @truncate(c.arguments.len));
            },
            .Member => |m| {
                try self.compileNode(m.object);
                const atom = try self.atom_table.intern(m.property);
                try self.code.emitOp(.GetProp);
                try self.code.emitU16(@truncate(atom.toU32()));
            },
            .ArrayLiteral => |arr| {
                for (arr) |elem| {
                    try self.compileNode(elem);
                }
                try self.code.emitOp(.CreateArray);
                try self.code.emitU16(@truncate(arr.len));
            },
            .ObjectLiteral => |props| {
                try self.code.emitOp(.CreateObject);
                for (props) |prop| {
                    try self.code.emitOp(.Dup);
                    try self.compileNode(prop.value);
                    const atom = try self.atom_table.intern(prop.key);
                    try self.code.emitOp(.SetProp);
                    try self.code.emitU16(@truncate(atom.toU32()));
                    try self.code.emitOp(.Pop);
                }
            },
            .Block => |stmts| {
                for (stmts) |stmt| {
                    try self.compileNode(stmt);
                }
            },
            .If => |i| {
                try self.compileNode(i.condition);
                try self.code.emitOp(.JumpIfFalse);
                const jump_patch_idx = self.code.instructions.items.len;
                try self.code.emitI32(0); // placeholder

                try self.compileNode(i.consequent);

                if (i.alternate) |alt| {
                    try self.code.emitOp(.Jump);
                    const else_patch_idx = self.code.instructions.items.len;
                    try self.code.emitI32(0);

                    // Patch JumpIfFalse offset
                    const if_false_offset: i32 = @intCast(self.code.instructions.items.len - (jump_patch_idx + 4));
                    std.mem.writeInt(i32, self.code.instructions.items[jump_patch_idx..][0..4], if_false_offset, .little);

                    try self.compileNode(alt);

                    const else_offset: i32 = @intCast(self.code.instructions.items.len - (else_patch_idx + 4));
                    std.mem.writeInt(i32, self.code.instructions.items[else_patch_idx..][0..4], else_offset, .little);
                } else {
                    const if_false_offset: i32 = @intCast(self.code.instructions.items.len - (jump_patch_idx + 4));
                    std.mem.writeInt(i32, self.code.instructions.items[jump_patch_idx..][0..4], if_false_offset, .little);
                }
            },
            .While => |w| {
                const loop_start_idx = self.code.instructions.items.len;
                try self.compileNode(w.condition);
                try self.code.emitOp(.JumpIfFalse);
                const exit_patch_idx = self.code.instructions.items.len;
                try self.code.emitI32(0); // placeholder for loop exit

                try self.compileNode(w.body);

                // Jump back to loop start
                try self.code.emitOp(.Jump);
                const jump_back_offset: i32 = @as(i32, @intCast(loop_start_idx)) - @as(i32, @intCast(self.code.instructions.items.len + 4));
                try self.code.emitI32(jump_back_offset);

                // Patch loop exit offset
                const exit_offset: i32 = @intCast(self.code.instructions.items.len - (exit_patch_idx + 4));
                std.mem.writeInt(i32, self.code.instructions.items[exit_patch_idx..][0..4], exit_offset, .little);
            },
            .For => |f| {
                if (f.init) |i| try self.compileNode(i);
                const loop_start_idx = self.code.instructions.items.len;
                var exit_patch_idx: ?usize = null;
                if (f.condition) |t| {
                    try self.compileNode(t);
                    try self.code.emitOp(.JumpIfFalse);
                    exit_patch_idx = self.code.instructions.items.len;
                    try self.code.emitI32(0);
                }
                try self.compileNode(f.body);
                if (f.update) |u| try self.compileNode(u);
                try self.code.emitOp(.Jump);
                const jump_back_offset: i32 = @as(i32, @intCast(loop_start_idx)) - @as(i32, @intCast(self.code.instructions.items.len + 4));
                try self.code.emitI32(jump_back_offset);
                if (exit_patch_idx) |epi| {
                    const exit_offset: i32 = @intCast(self.code.instructions.items.len - (epi + 4));
                    std.mem.writeInt(i32, self.code.instructions.items[epi..][0..4], exit_offset, .little);
                }
            },
            .Return => |r| {
                if (r) |val| {
                    try self.compileNode(val);
                } else {
                    const c_idx = try self.code.addConstant(JSValue.undefined_val);
                    try self.code.emitOp(.LoadConst);
                    try self.code.emitU16(c_idx);
                }
                try self.code.emitOp(.Return);
            },
            .FunctionDecl => |fd| {
                const fn_block = try self.allocator.create(CodeBlock);
                fn_block.* = CodeBlock.init(self.allocator, fd.name);
                for (fd.params) |p| {
                    _ = try fn_block.resolveOrAddLocal(p);
                }

                var fn_compiler = BytecodeCompiler{
                    .allocator = self.allocator,
                    .atom_table = self.atom_table,
                    .code = fn_block.*,
                };
                try fn_compiler.compileNode(fd.body);
                try fn_compiler.code.emitOp(.Return);
                fn_block.* = fn_compiler.code;

                const fn_idx: u16 = @truncate(self.code.functions.items.len);
                try self.code.functions.append(self.allocator, fn_block);

                try self.code.emitOp(.CreateFunction);
                try self.code.emitU16(fn_idx);

                if (fd.name.len > 0) {
                    const slot = try self.code.resolveOrAddLocal(fd.name);
                    try self.code.emitOp(.Dup);
                    try self.code.emitOp(.StoreLocal);
                    try self.code.emitU16(slot);

                    const atom = try self.atom_table.intern(fd.name);
                    try self.code.emitOp(.StoreGlobal);
                    try self.code.emitU16(@truncate(atom.toU32()));
                }
            },
            else => {},
        }
    }
};

test "bytecode compilation" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const Parser = @import("parser.zig").Parser;
    const src = "let x = 10; let y = 20; return x + y;";
    var parser = Parser.init(allocator, src);
    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    var compiler = BytecodeCompiler.init(allocator, atom_table, "test");
    var code = try compiler.compile(ast);
    defer code.deinit();

    try std.testing.expect(code.instructions.items.len > 0);
    try std.testing.expectEqual(@as(usize, 2), code.local_names.items.len);
}
