//! Virtual Machine bytecode interpreter and execution environment.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const Shape = @import("object.zig").Shape;
const CodeBlock = @import("bytecode.zig").CodeBlock;
const OpCode = @import("bytecode.zig").OpCode;
const GarbageCollector = @import("gc.zig").GarbageCollector;
const JITCompiler = @import("jit.zig").JITCompiler;

pub const CallFrame = struct {
    code: *const CodeBlock,
    ip: usize = 0,
    locals: []JSValue,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    gc: *GarbageCollector,
    global_object: *JSObject,
    stack: [1024]JSValue = undefined,
    stack_top: usize = 0,
    frames: [64]CallFrame = undefined,
    frame_count: usize = 0,
    jit: ?*JITCompiler = null,
    invocation_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable, gc: *GarbageCollector) !*VM {
        const vm = try allocator.create(VM);
        const global_obj = try gc.allocateObject(null);
        try gc.registerRootObject(global_obj);

        vm.* = .{
            .allocator = allocator,
            .atom_table = atom_table,
            .gc = gc,
            .global_object = global_obj,
            .stack_top = 0,
            .frame_count = 0,
            .jit = null,
            .invocation_count = 0,
        };
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.allocator.destroy(self);
    }

    pub fn push(self: *VM, val: JSValue) !void {
        if (self.stack_top >= self.stack.len) return error.StackOverflow;
        self.stack[self.stack_top] = val;
        self.stack_top += 1;
    }

    pub fn pop(self: *VM) JSValue {
        if (self.stack_top == 0) return JSValue.undefined_val;
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    pub fn peek(self: *VM) JSValue {
        if (self.stack_top == 0) return JSValue.undefined_val;
        return self.stack[self.stack_top - 1];
    }

    pub fn execute(self: *VM, code: *const CodeBlock) !JSValue {
        self.invocation_count += 1;

        // Try JIT compilation if hot and JIT is available
        if (self.jit) |jit_comp| {
            if (self.invocation_count >= jit_comp.compilation_threshold) {
                if (jit_comp.compile(code)) |jit_fn| {
                    const local_slots = try self.allocator.alloc(JSValue, code.local_names.items.len);
                    defer self.allocator.free(local_slots);
                    @memset(local_slots, JSValue.undefined_val);

                    var temp_stack: [256]JSValue = undefined;
                    return jit_fn(self, code, local_slots.ptr, &temp_stack);
                } else |_| {}
            }
        }

        const local_slots = try self.allocator.alloc(JSValue, code.local_names.items.len);
        defer self.allocator.free(local_slots);
        @memset(local_slots, JSValue.undefined_val);

        return self.executeWithLocals(code, local_slots);
    }

    pub fn executeWithLocals(self: *VM, code: *const CodeBlock, locals: []JSValue) !JSValue {
        if (self.frame_count >= self.frames.len) return error.CallStackOverflow;
        self.frames[self.frame_count] = CallFrame{
            .code = code,
            .ip = 0,
            .locals = locals,
        };
        self.frame_count += 1;
        defer self.frame_count -= 1;

        var frame = &self.frames[self.frame_count - 1];
        const instrs = code.instructions.items;

        while (frame.ip < instrs.len) {
            const op_byte = instrs[frame.ip];
            frame.ip += 1;
            const op: OpCode = @enumFromInt(op_byte);

            switch (op) {
                .LoadConst => {
                    const c_idx = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    try self.push(code.constants.items[c_idx]);
                },
                .LoadLocal => {
                    const slot = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    try self.push(frame.locals[slot]);
                },
                .StoreLocal => {
                    const slot = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    frame.locals[slot] = self.pop();
                },
                .LoadGlobal => {
                    const atom_u32 = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    const atom = AtomId.fromU32(atom_u32);
                    const val = self.global_object.getProperty(atom) orelse JSValue.undefined_val;
                    try self.push(val);
                },
                .StoreGlobal => {
                    const atom_u32 = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    const atom = AtomId.fromU32(atom_u32);
                    const val = self.pop();
                    try self.global_object.setProperty(self.allocator, atom, val);
                },
                .GetProp => {
                    const atom_u32 = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    const atom = AtomId.fromU32(atom_u32);
                    const target = self.pop();
                    if (target.toObject()) |obj| {
                        const val = obj.getProperty(atom) orelse JSValue.undefined_val;
                        try self.push(val);
                    } else {
                        try self.push(JSValue.undefined_val);
                    }
                },
                .SetProp => {
                    const atom_u32 = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    const atom = AtomId.fromU32(atom_u32);
                    const val = self.pop();
                    const target = self.pop();
                    if (target.toObject()) |obj| {
                        try obj.setProperty(self.allocator, atom, val);
                    }
                    try self.push(val);
                },
                .Add => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a.isInt32() and b.isInt32()) {
                        try self.push(JSValue.fromInt32(a.toInt32() +% b.toInt32()));
                    } else {
                        try self.push(JSValue.fromFloat64(a.toFloat64() + b.toFloat64()));
                    }
                },
                .Sub => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a.isInt32() and b.isInt32()) {
                        try self.push(JSValue.fromInt32(a.toInt32() -% b.toInt32()));
                    } else {
                        try self.push(JSValue.fromFloat64(a.toFloat64() - b.toFloat64()));
                    }
                },
                .Mul => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a.isInt32() and b.isInt32()) {
                        try self.push(JSValue.fromInt32(a.toInt32() *% b.toInt32()));
                    } else {
                        try self.push(JSValue.fromFloat64(a.toFloat64() * b.toFloat64()));
                    }
                },
                .Div => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromFloat64(a.toFloat64() / b.toFloat64()));
                },
                .Mod => {
                    const b = self.pop();
                    const a = self.pop();
                    if (b.toInt32() != 0) {
                        try self.push(JSValue.fromInt32(@rem(a.toInt32(), b.toInt32())));
                    } else {
                        try self.push(JSValue.fromFloat64(std.math.nan(f64)));
                    }
                },
                .Equal, .StrictEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a.isInt32() and b.isInt32()) {
                        try self.push(JSValue.fromBoolean(a.toInt32() == b.toInt32()));
                    } else if (a.isFloat64() or b.isFloat64()) {
                        try self.push(JSValue.fromBoolean(a.toFloat64() == b.toFloat64()));
                    } else {
                        try self.push(JSValue.fromBoolean(a.raw == b.raw));
                    }
                },
                .NotEqual, .StrictNotEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(a.raw != b.raw));
                },
                .Less => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(a.toFloat64() < b.toFloat64()));
                },
                .LessEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(a.toFloat64() <= b.toFloat64()));
                },
                .Greater => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(a.toFloat64() > b.toFloat64()));
                },
                .GreaterEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(a.toFloat64() >= b.toFloat64()));
                },
                .Not => {
                    const a = self.pop();
                    try self.push(JSValue.fromBoolean(!a.toBoolean()));
                },
                .Negate => {
                    const a = self.pop();
                    if (a.isInt32()) {
                        try self.push(JSValue.fromInt32(-%a.toInt32()));
                    } else {
                        try self.push(JSValue.fromFloat64(-a.toFloat64()));
                    }
                },
                .Jump => {
                    const offset = std.mem.readInt(i32, instrs[frame.ip..][0..4], .little);
                    frame.ip += 4;
                    const new_ip: isize = @as(isize, @intCast(frame.ip)) + @as(isize, offset);
                    frame.ip = @intCast(new_ip);
                },
                .JumpIfFalse => {
                    const offset = std.mem.readInt(i32, instrs[frame.ip..][0..4], .little);
                    frame.ip += 4;
                    const condition = self.pop();
                    if (!condition.toBoolean()) {
                        const new_ip: isize = @as(isize, @intCast(frame.ip)) + @as(isize, offset);
                        frame.ip = @intCast(new_ip);
                    }
                },
                .CreateFunction => {
                    const fn_idx = std.mem.readInt(u16, instrs[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    const fn_code = frame.code.functions.items[fn_idx];
                    const fn_obj = try self.gc.allocateObject(null);
                    fn_obj.builtin_type = .Function;
                    fn_obj.code_block = fn_code;
                    try self.push(JSValue.fromObject(fn_obj));
                },
                .Call => {
                    const arg_count = instrs[frame.ip];
                    frame.ip += 1;

                    const callee = self.pop();
                    var args_buf: [16]JSValue = undefined;
                    var i: usize = arg_count;
                    while (i > 0) : (i -= 1) {
                        args_buf[i - 1] = self.pop();
                    }

                    if (callee.toObject()) |obj| {
                        if (obj.native_fn) |n_fn| {
                            const res = try n_fn(obj.native_ctx orelse @ptrCast(self), JSValue.undefined_val, args_buf[0..arg_count]);
                            try self.push(res);
                        } else if (obj.code_block) |cb_ptr| {
                            const target_code: *const CodeBlock = @ptrCast(@alignCast(cb_ptr));
                            const local_count = @max(target_code.local_names.items.len, @as(usize, arg_count));
                            const locals_mem = try self.allocator.alloc(JSValue, local_count);
                            defer self.allocator.free(locals_mem);
                            @memset(locals_mem, JSValue.undefined_val);
                            for (args_buf[0..arg_count], 0..) |arg, a_idx| {
                                locals_mem[a_idx] = arg;
                            }
                            const res = try self.executeWithLocals(target_code, locals_mem);
                            try self.push(res);
                        } else {
                            try self.push(JSValue.undefined_val);
                        }
                    } else {
                        try self.push(JSValue.undefined_val);
                    }
                },
                .Return => {
                    if (self.stack_top > 0) {
                        return self.pop();
                    }
                    return JSValue.undefined_val;
                },
                .Pop => {
                    _ = self.pop();
                },
                .Dup => {
                    const top = self.peek();
                    try self.push(top);
                },
                else => {},
            }
        }

        return JSValue.undefined_val;
    }
};

test "interpreter evaluate bytecode" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    const src = "let a = 15; let b = 27; return a + b;";
    var parser = Parser.init(allocator, src);
    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    var compiler = BytecodeCompiler.init(allocator, atom_table, "main");
    var code = try compiler.compile(ast);
    defer code.deinit();

    const res = try vm.execute(&code);
    try std.testing.expectEqual(@as(f64, 42.0), res.toFloat64());
}
