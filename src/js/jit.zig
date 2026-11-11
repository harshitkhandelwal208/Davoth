//! Baseline x86-64 JIT compiler emitting native machine code via executable mmap pages.
const std = @import("std");
const posix = std.posix;
const CodeBlock = @import("bytecode.zig").CodeBlock;
const OpCode = @import("bytecode.zig").OpCode;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;

pub const JITFn = *const fn (
    vm: *anyopaque,
    code: *const CodeBlock,
    locals: [*]JSValue,
    stack: [*]JSValue,
) callconv(.c) JSValue;

// Runtime helpers called by JIT-compiled machine code
pub export fn davoth_jit_helper_add(left: JSValue, right: JSValue) JSValue {
    if (left.isFloat64() and right.isFloat64()) {
        return JSValue.fromFloat64(left.toFloat64() + right.toFloat64());
    }
    if (left.isInt32() and right.isInt32()) {
        const sum = @as(i64, left.toInt32()) + @as(i64, right.toInt32());
        if (sum >= std.math.minInt(i32) and sum <= std.math.maxInt(i32)) {
            return JSValue.fromInt32(@intCast(sum));
        }
        return JSValue.fromFloat64(@floatFromInt(sum));
    }
    // Mixed numeric fallback
    return JSValue.fromFloat64(left.toFloat64() + right.toFloat64());
}

pub export fn davoth_jit_helper_sub(left: JSValue, right: JSValue) JSValue {
    if (left.isInt32() and right.isInt32()) {
        const diff = @as(i64, left.toInt32()) - @as(i64, right.toInt32());
        if (diff >= std.math.minInt(i32) and diff <= std.math.maxInt(i32)) {
            return JSValue.fromInt32(@intCast(diff));
        }
        return JSValue.fromFloat64(@floatFromInt(diff));
    }
    return JSValue.fromFloat64(left.toFloat64() - right.toFloat64());
}

pub export fn davoth_jit_helper_mul(left: JSValue, right: JSValue) JSValue {
    if (left.isInt32() and right.isInt32()) {
        const prod = @as(i64, left.toInt32()) * @as(i64, right.toInt32());
        if (prod >= std.math.minInt(i32) and prod <= std.math.maxInt(i32)) {
            return JSValue.fromInt32(@intCast(prod));
        }
        return JSValue.fromFloat64(@floatFromInt(prod));
    }
    return JSValue.fromFloat64(left.toFloat64() * right.toFloat64());
}

pub export fn davoth_jit_helper_div(left: JSValue, right: JSValue) JSValue {
    const r = right.toFloat64();
    if (r == 0.0) return JSValue.fromFloat64(std.math.inf(f64));
    return JSValue.fromFloat64(left.toFloat64() / r);
}

pub export fn davoth_jit_helper_cmp(left: JSValue, right: JSValue, op_code: u8) JSValue {
    const l = left.toFloat64();
    const r = right.toFloat64();
    const res = switch (op_code) {
        13, 14 => left.raw == right.raw or l == r, // Equal, StrictEqual
        15, 16 => left.raw != right.raw and l != r, // NotEqual, StrictNotEqual
        17 => l < r, // Less
        18 => l <= r, // LessEqual
        19 => l > r, // Greater
        20 => l >= r, // GreaterEqual
        else => false,
    };
    return JSValue.fromBoolean(res);
}

pub const JITCompiler = struct {
    allocator: std.mem.Allocator,
    executable_pages: std.ArrayList([]align(4096) u8),
    compilation_threshold: u32 = 10,
    total_bytes_emitted: usize = 0,
    deopt_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) JITCompiler {
        return .{
            .allocator = allocator,
            .executable_pages = .empty,
            .compilation_threshold = 10,
            .total_bytes_emitted = 0,
            .deopt_count = 0,
        };
    }

    pub fn deinit(self: *JITCompiler) void {
        for (self.executable_pages.items) |page| {
            posix.munmap(page);
        }
        self.executable_pages.deinit(self.allocator);
    }

    pub fn compile(self: *JITCompiler, code: *const CodeBlock) !JITFn {
        // Allocate a 4KB executable page with initial W permission
        const page_size = 4096;
        const page = try posix.mmap(
            null,
            page_size,
            posix.PROT{ .READ = true, .WRITE = true },
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        errdefer posix.munmap(page);

        var buf: [2048]u8 = undefined;
        var len: usize = 0;

        // System V AMD64 ABI:
        // Arg 0 (RDI): vm pointer
        // Arg 1 (RSI): code pointer
        // Arg 2 (RDX): locals pointer ([*]JSValue)
        // Arg 3 (RCX): stack pointer ([*]JSValue)

        // Prologue:
        // push rbp
        // mov rbp, rsp
        // push rbx
        // push r12
        // push r13
        // push r14
        // push r15
        // sub rsp, 8 (align to 16 bytes)
        buf[len] = 0x55; len += 1;
        buf[len] = 0x48; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0xE5; len += 1;
        buf[len] = 0x53; len += 1;
        buf[len] = 0x41; len += 1; buf[len] = 0x54; len += 1; // push r12
        buf[len] = 0x41; len += 1; buf[len] = 0x55; len += 1; // push r13
        buf[len] = 0x41; len += 1; buf[len] = 0x56; len += 1; // push r14
        buf[len] = 0x41; len += 1; buf[len] = 0x57; len += 1; // push r15
        buf[len] = 0x48; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEC; len += 1; buf[len] = 0x08; len += 1;

        // r12 = vm (RDI)
        buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0xFC; len += 1;
        // r13 = code (RSI)
        buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0xF5; len += 1;
        // r14 = locals (RDX)
        buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0xD6; len += 1;
        // r15 = stack pointer (RCX)
        buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0xCF; len += 1;

        const instrs = code.instructions.items;
        var ip: usize = 0;

        while (ip < instrs.len) {
            const op_byte = instrs[ip];
            ip += 1;
            const op: OpCode = @enumFromInt(op_byte);

            switch (op) {
                .LoadConst => {
                    const c_idx = std.mem.readInt(u16, instrs[ip..][0..2], .little);
                    ip += 2;
                    const c_val = code.constants.items[c_idx].raw;

                    // mov rax, imm64
                    buf[len] = 0x48; len += 1; buf[len] = 0xB8; len += 1;
                    std.mem.writeInt(u64, buf[len..][0..8], c_val, .little);
                    len += 8;

                    // mov [r15], rax; add r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x07; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC7; len += 1; buf[len] = 0x08; len += 1;
                },
                .LoadLocal => {
                    const slot = std.mem.readInt(u16, instrs[ip..][0..2], .little);
                    ip += 2;

                    // mov rax, [r14 + slot*8]
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x86; len += 1;
                    std.mem.writeInt(u32, buf[len..][0..4], @as(u32, slot) * 8, .little);
                    len += 4;

                    // mov [r15], rax; add r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x07; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC7; len += 1; buf[len] = 0x08; len += 1;
                },
                .StoreLocal => {
                    const slot = std.mem.readInt(u16, instrs[ip..][0..2], .little);
                    ip += 2;

                    // sub r15, 8; mov rax, [r15]
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x07; len += 1;

                    // mov [r14 + slot*8], rax
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x86; len += 1;
                    std.mem.writeInt(u32, buf[len..][0..4], @as(u32, slot) * 8, .little);
                    len += 4;
                },
                .Add, .Sub, .Mul, .Div => {
                    // sub r15, 8; mov rsi, [r15] (right)
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x37; len += 1;

                    // sub r15, 8; mov rdi, [r15] (left)
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x3F; len += 1;

                    // Call helper function
                    const helper_fn_addr: usize = switch (op) {
                        .Add => @intFromPtr(&davoth_jit_helper_add),
                        .Sub => @intFromPtr(&davoth_jit_helper_sub),
                        .Mul => @intFromPtr(&davoth_jit_helper_mul),
                        .Div => @intFromPtr(&davoth_jit_helper_div),
                        else => unreachable,
                    };

                    // mov rax, helper_fn_addr; call rax
                    buf[len] = 0x48; len += 1; buf[len] = 0xB8; len += 1;
                    std.mem.writeInt(u64, buf[len..][0..8], helper_fn_addr, .little);
                    len += 8;
                    buf[len] = 0xFF; len += 1; buf[len] = 0xD0; len += 1;

                    // Push result: mov [r15], rax; add r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x07; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC7; len += 1; buf[len] = 0x08; len += 1;
                },
                .Equal, .StrictEqual, .NotEqual, .StrictNotEqual, .Less, .LessEqual, .Greater, .GreaterEqual => {
                    // sub r15, 8; mov rsi, [r15] (right)
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x37; len += 1;

                    // sub r15, 8; mov rdi, [r15] (left)
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x3F; len += 1;

                    // mov edx, op_code
                    buf[len] = 0xBA; len += 1;
                    std.mem.writeInt(u32, buf[len..][0..4], op_byte, .little);
                    len += 4;

                    // mov rax, &davoth_jit_helper_cmp; call rax
                    buf[len] = 0x48; len += 1; buf[len] = 0xB8; len += 1;
                    std.mem.writeInt(u64, buf[len..][0..8], @intFromPtr(&davoth_jit_helper_cmp), .little);
                    len += 8;
                    buf[len] = 0xFF; len += 1; buf[len] = 0xD0; len += 1;

                    // Push result: mov [r15], rax; add r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x07; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC7; len += 1; buf[len] = 0x08; len += 1;
                },
                .Pop => {
                    // sub r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                },
                .Dup => {
                    // mov rax, [r15 - 8]; mov [r15], rax; add r15, 8
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x47; len += 1; buf[len] = 0xF8; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x89; len += 1; buf[len] = 0x07; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC7; len += 1; buf[len] = 0x08; len += 1;
                },
                .Return => {
                    // sub r15, 8; mov rax, [r15]
                    buf[len] = 0x49; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xEF; len += 1; buf[len] = 0x08; len += 1;
                    buf[len] = 0x49; len += 1; buf[len] = 0x8B; len += 1; buf[len] = 0x07; len += 1;
                    break;
                },
                else => {
                    // Deoptimize on complex control flow or unhandled opcodes
                    self.deopt_count += 1;
                    return error.DeoptimizationRequired;
                },
            }
        }

        // Epilogue:
        // add rsp, 8
        // pop r15
        // pop r14
        // pop r13
        // pop r12
        // pop rbx
        // pop rbp
        // ret
        buf[len] = 0x48; len += 1; buf[len] = 0x83; len += 1; buf[len] = 0xC4; len += 1; buf[len] = 0x08; len += 1;
        buf[len] = 0x41; len += 1; buf[len] = 0x5F; len += 1; // pop r15
        buf[len] = 0x41; len += 1; buf[len] = 0x5E; len += 1; // pop r14
        buf[len] = 0x41; len += 1; buf[len] = 0x5D; len += 1; // pop r13
        buf[len] = 0x41; len += 1; buf[len] = 0x5C; len += 1; // pop r12
        buf[len] = 0x5B; len += 1; // pop rbx
        buf[len] = 0x5D; len += 1; // pop rbp
        buf[len] = 0xC3; len += 1; // ret

        @memcpy(page[0..len], buf[0..len]);

        // Enforce W^X security: change protection from W to RX
        _ = posix.system.mprotect(page.ptr, page_size, posix.PROT{ .READ = true, .EXEC = true });

        try self.executable_pages.append(self.allocator, page);
        self.total_bytes_emitted += len;

        const func: JITFn = @ptrCast(page.ptr);
        return func;
    }
};

test "baseline x86-64 jit arithmetic execution" {
    const allocator = std.testing.allocator;
    var jit = JITCompiler.init(allocator);
    defer jit.deinit();

    var code = CodeBlock.init(allocator, "test_jit");
    defer code.deinit();

    // let a = 10;
    // let b = 32;
    // return a + b;
    const c1 = try code.addConstant(JSValue.fromFloat64(10.0));
    const c2 = try code.addConstant(JSValue.fromFloat64(32.0));
    _ = try code.addLocal("a");
    _ = try code.addLocal("b");

    try code.emitOp(.LoadConst);
    try code.emitU16(c1);
    try code.emitOp(.StoreLocal);
    try code.emitU16(0);

    try code.emitOp(.LoadConst);
    try code.emitU16(c2);
    try code.emitOp(.StoreLocal);
    try code.emitU16(1);

    try code.emitOp(.LoadLocal);
    try code.emitU16(0);
    try code.emitOp(.LoadLocal);
    try code.emitU16(1);
    try code.emitOp(.Add);
    try code.emitOp(.Return);

    const func = try jit.compile(&code);

    var locals: [16]JSValue = undefined;
    var stack: [128]JSValue = undefined;

    const dummy_vm: usize = 0;
    const result = func(@ptrCast(&dummy_vm), &code, &locals, &stack);

    try std.testing.expectEqual(@as(f64, 42.0), result.toFloat64());
    try std.testing.expect(jit.total_bytes_emitted > 0);
}
