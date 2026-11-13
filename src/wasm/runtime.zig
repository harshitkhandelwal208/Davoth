//! WebAssembly execution runtime and linear memory engine.
const std = @import("std");
const ValueType = @import("types.zig").ValueType;
const WasmValue = @import("types.zig").WasmValue;
const WasmModule = @import("decoder.zig").WasmModule;
const Decoder = @import("decoder.zig").Decoder;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const PAGE_SIZE: usize = 65536; // 64KB

pub const LinearMemory = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    max_pages: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, initial_pages: u32, max_pages: ?u32) !LinearMemory {
        var list: std.ArrayList(u8) = .empty;
        const total = @as(usize, initial_pages) * PAGE_SIZE;
        try list.appendNTimes(allocator, 0, total);
        SubsystemMemoryTracker.global.recordAlloc(.WASMHeap, total);

        return LinearMemory{
            .allocator = allocator,
            .bytes = list,
            .max_pages = max_pages,
        };
    }

    pub fn deinit(self: *LinearMemory) void {
        SubsystemMemoryTracker.global.recordFree(.WASMHeap, self.bytes.items.len);
        self.bytes.deinit(self.allocator);
    }

    pub fn grow(self: *LinearMemory, additional_pages: u32) !u32 {
        const current_pages: u32 = @truncate(self.bytes.items.len / PAGE_SIZE);
        if (self.max_pages) |max| {
            if (current_pages + additional_pages > max) return error.ExceedsMemoryLimit;
        }
        const added_bytes = @as(usize, additional_pages) * PAGE_SIZE;
        try self.bytes.appendNTimes(self.allocator, 0, added_bytes);
        SubsystemMemoryTracker.global.recordAlloc(.WASMHeap, added_bytes);
        return current_pages;
    }

    pub fn loadI32(self: *const LinearMemory, offset: usize) !i32 {
        if (offset + 4 > self.bytes.items.len) return error.OutOfBoundsMemoryAccess;
        return std.mem.readInt(i32, self.bytes.items[offset..][0..4], .little);
    }

    pub fn storeI32(self: *LinearMemory, offset: usize, val: i32) !void {
        if (offset + 4 > self.bytes.items.len) return error.OutOfBoundsMemoryAccess;
        std.mem.writeInt(i32, self.bytes.items[offset..][0..4], val, .little);
    }
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    module: *const WasmModule,
    memory: ?LinearMemory,
    stack: [1024]WasmValue = undefined,
    stack_top: usize = 0,

    pub fn init(allocator: std.mem.Allocator, module: *const WasmModule) !*Instance {
        const inst = try allocator.create(Instance);
        var mem: ?LinearMemory = null;
        if (module.memory_limits) |lim| {
            mem = try LinearMemory.init(allocator, lim.min, lim.max);
        }

        inst.* = .{
            .allocator = allocator,
            .module = module,
            .memory = mem,
            .stack_top = 0,
        };
        return inst;
    }

    pub fn deinit(self: *Instance) void {
        if (self.memory) |*m| m.deinit();
        self.allocator.destroy(self);
    }

    pub fn push(self: *Instance, val: WasmValue) !void {
        if (self.stack_top >= self.stack.len) return error.StackOverflow;
        self.stack[self.stack_top] = val;
        self.stack_top += 1;
    }

    pub fn pop(self: *Instance) WasmValue {
        if (self.stack_top == 0) return .{ .I32 = 0 };
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    pub fn invoke(self: *Instance, export_name: []const u8, args: []const WasmValue) !WasmValue {
        for (self.module.exports.items) |exp| {
            if (std.mem.eql(u8, exp.name, export_name) and exp.kind == 0) {
                return self.invokeFunction(exp.index, args);
            }
        }
        return error.ExportNotFound;
    }

    pub fn invokeFunction(self: *Instance, func_index: u32, args: []const WasmValue) !WasmValue {
        if (func_index >= self.module.code_bodies.items.len) return error.InvalidFunctionIndex;
        const body = self.module.code_bodies.items[func_index];

        var locals: [64]WasmValue = undefined;
        var local_count: usize = 0;

        for (args) |arg| {
            locals[local_count] = arg;
            local_count += 1;
        }

        var extra: u32 = 0;
        while (extra < body.local_count and local_count < locals.len) : (extra += 1) {
            locals[local_count] = .{ .I32 = 0 };
            local_count += 1;
        }

        const code = body.code;
        var ip: usize = 0;

        while (ip < code.len) {
            const opcode = code[ip];
            ip += 1;

            switch (opcode) {
                0x20 => { // local.get
                    var dec = Decoder.init(code[ip..]);
                    const idx = try dec.readUleb128();
                    ip += dec.cursor;
                    if (idx < local_count) {
                        try self.push(locals[idx]);
                    }
                },
                0x21 => { // local.set
                    var dec = Decoder.init(code[ip..]);
                    const idx = try dec.readUleb128();
                    ip += dec.cursor;
                    if (idx < local_count) {
                        locals[idx] = self.pop();
                    }
                },
                0x41 => { // i32.const
                    var dec = Decoder.init(code[ip..]);
                    const val = try dec.readSleb128();
                    ip += dec.cursor;
                    try self.push(.{ .I32 = val });
                },
                0x6A => { // i32.add
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a +% b });
                },
                0x6B => { // i32.sub
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a -% b });
                },
                0x6C => { // i32.mul
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a *% b });
                },
                0x6D => { // i32.div_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    if (b == 0) return error.DivisionByZero;
                    try self.push(.{ .I32 = @divTrunc(a, b) });
                },
                0x6E => { // i32.div_u
                    const b: u32 = @bitCast(self.pop().toI32());
                    const a: u32 = @bitCast(self.pop().toI32());
                    if (b == 0) return error.DivisionByZero;
                    try self.push(.{ .I32 = @bitCast(a / b) });
                },
                0x6F => { // i32.rem_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    if (b == 0) return error.DivisionByZero;
                    try self.push(.{ .I32 = @rem(a, b) });
                },
                0x70 => { // i32.rem_u
                    const b: u32 = @bitCast(self.pop().toI32());
                    const a: u32 = @bitCast(self.pop().toI32());
                    if (b == 0) return error.DivisionByZero;
                    try self.push(.{ .I32 = @bitCast(a % b) });
                },
                0x71 => { // i32.and
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a & b });
                },
                0x72 => { // i32.or
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a | b });
                },
                0x73 => { // i32.xor
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a ^ b });
                },
                0x74 => { // i32.shl
                    const b = @as(u5, @truncate(@as(u32, @bitCast(self.pop().toI32()))));
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a << b });
                },
                0x75 => { // i32.shr_s
                    const b = @as(u5, @truncate(@as(u32, @bitCast(self.pop().toI32()))));
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = a >> b });
                },
                0x76 => { // i32.shr_u
                    const b = @as(u5, @truncate(@as(u32, @bitCast(self.pop().toI32()))));
                    const a: u32 = @bitCast(self.pop().toI32());
                    try self.push(.{ .I32 = @bitCast(a >> b) });
                },
                0x45 => { // i32.eqz
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a == 0) 1 else 0 });
                },
                0x46 => { // i32.eq
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a == b) 1 else 0 });
                },
                0x47 => { // i32.ne
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a != b) 1 else 0 });
                },
                0x48 => { // i32.lt_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a < b) 1 else 0 });
                },
                0x49 => { // i32.lt_u
                    const b: u32 = @bitCast(self.pop().toI32());
                    const a: u32 = @bitCast(self.pop().toI32());
                    try self.push(.{ .I32 = if (a < b) 1 else 0 });
                },
                0x4A => { // i32.gt_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a > b) 1 else 0 });
                },
                0x4B => { // i32.gt_u
                    const b: u32 = @bitCast(self.pop().toI32());
                    const a: u32 = @bitCast(self.pop().toI32());
                    try self.push(.{ .I32 = if (a > b) 1 else 0 });
                },
                0x4C => { // i32.le_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a <= b) 1 else 0 });
                },
                0x4E => { // i32.ge_s
                    const b = self.pop().toI32();
                    const a = self.pop().toI32();
                    try self.push(.{ .I32 = if (a >= b) 1 else 0 });
                },
                0x28 => { // i32.load
                    var dec = Decoder.init(code[ip..]);
                    _ = try dec.readUleb128(); // align
                    const offset = try dec.readUleb128();
                    ip += dec.cursor;
                    const base = @as(u32, @bitCast(self.pop().toI32()));
                    if (self.memory) |*mem| {
                        const val = try mem.loadI32(@as(usize, base) + @as(usize, offset));
                        try self.push(.{ .I32 = val });
                    }
                },
                0x36 => { // i32.store
                    var dec = Decoder.init(code[ip..]);
                    _ = try dec.readUleb128(); // align
                    const offset = try dec.readUleb128();
                    ip += dec.cursor;
                    const val = self.pop().toI32();
                    const base = @as(u32, @bitCast(self.pop().toI32()));
                    if (self.memory) |*mem| {
                        try mem.storeI32(@as(usize, base) + @as(usize, offset), val);
                    }
                },
                0x1A => { // drop
                    _ = self.pop();
                },
                0x1B => { // select
                    const c_val = self.pop().toI32();
                    const val2 = self.pop();
                    const val1 = self.pop();
                    try self.push(if (c_val != 0) val1 else val2);
                },
                0x01 => {}, // nop
                0x0F => { // return
                    return self.pop();
                },
                0x0B => { // end
                    if (self.stack_top > 0) return self.pop();
                    return .{ .I32 = 0 };
                },
                else => {},
            }
        }

        if (self.stack_top > 0) return self.pop();
        return .{ .I32 = 0 };
    }
};

test "wasm linear memory and execution" {
    const allocator = std.testing.allocator;
    var mem = try LinearMemory.init(allocator, 1, 2);
    defer mem.deinit();

    try mem.storeI32(128, 123456);
    const read = try mem.loadI32(128);
    try std.testing.expectEqual(@as(i32, 123456), read);

    const old_pages = try mem.grow(1);
    try std.testing.expectEqual(@as(u32, 1), old_pages);
}

test "wasm instruction execution for arithmetic, comparisons, bitwise, and select" {
    const allocator = std.testing.allocator;

    var module = WasmModule{
        .types = .empty,
        .functions = .empty,
        .code_bodies = .empty,
        .exports = .empty,
        .memory_limits = .{ .min = 1, .max = 2 },
    };
    defer module.deinit(allocator);

    // Bytecode: i32.const 20, i32.const 5, i32.div_s, end
    const code_div = [_]u8{ 0x41, 20, 0x41, 5, 0x6D, 0x0B };
    try module.code_bodies.append(allocator, .{
        .local_count = 0,
        .code = &code_div,
    });

    // Bytecode: i32.const 12, i32.const 10, i32.and, end (12 & 10 = 8)
    const code_and = [_]u8{ 0x41, 12, 0x41, 10, 0x71, 0x0B };
    try module.code_bodies.append(allocator, .{
        .local_count = 0,
        .code = &code_and,
    });

    // Bytecode: i32.const 5, i32.const 10, i32.lt_s, end (5 < 10 = 1)
    const code_cmp = [_]u8{ 0x41, 5, 0x41, 10, 0x48, 0x0B };
    try module.code_bodies.append(allocator, .{
        .local_count = 0,
        .code = &code_cmp,
    });

    // Bytecode: i32.const 111, i32.const 222, i32.const 1, select, end (select 111)
    const code_sel = [_]u8{ 0x41, 111, 0x41, 126, 0x41, 1, 0x1B, 0x0B };
    try module.code_bodies.append(allocator, .{
        .local_count = 0,
        .code = &code_sel,
    });

    var inst = try Instance.init(allocator, &module);
    defer inst.deinit();

    const res_div = try inst.invokeFunction(0, &[_]WasmValue{});
    try std.testing.expectEqual(@as(i32, 4), res_div.toI32());

    const res_and = try inst.invokeFunction(1, &[_]WasmValue{});
    try std.testing.expectEqual(@as(i32, 8), res_and.toI32());

    const res_cmp = try inst.invokeFunction(2, &[_]WasmValue{});
    try std.testing.expectEqual(@as(i32, 1), res_cmp.toI32());

    const res_sel = try inst.invokeFunction(3, &[_]WasmValue{});
    try std.testing.expectEqual(@as(i32, 111), res_sel.toI32());
}
