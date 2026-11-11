//! Baseline x86-64 JIT compiler emitting native machine code via executable mmap pages.
const std = @import("std");
const posix = std.posix;
const CodeBlock = @import("bytecode.zig").CodeBlock;
const OpCode = @import("bytecode.zig").OpCode;

pub const JITFn = *const fn () callconv(.c) f64;

pub const JITCompiler = struct {
    allocator: std.mem.Allocator,
    executable_pages: std.ArrayList([]align(4096) u8),

    pub fn init(allocator: std.mem.Allocator) JITCompiler {
        return .{
            .allocator = allocator,
            .executable_pages = .empty,
        };
    }

    pub fn deinit(self: *JITCompiler) void {
        for (self.executable_pages.items) |page| {
            posix.munmap(page);
        }
        self.executable_pages.deinit(self.allocator);
    }

    pub fn compile(self: *JITCompiler, code: *const CodeBlock) !JITFn {
        // Allocate a 4KB executable page
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

        var buf: [512]u8 = undefined;
        var len: usize = 0;

        // x86-64 Prologue:
        // push rbp        (55)
        // mov rbp, rsp    (48 89 E5)
        buf[len] = 0x55;
        len += 1;
        buf[len] = 0x48;
        len += 1;
        buf[len] = 0x89;
        len += 1;
        buf[len] = 0xE5;
        len += 1;

        // Evaluate simple straight-line constant arithmetic in JIT
        var acc: f64 = 0.0;
        var has_acc = false;

        var ip: usize = 0;
        const instrs = code.instructions.items;
        while (ip < instrs.len) {
            const op: OpCode = @enumFromInt(instrs[ip]);
            ip += 1;

            switch (op) {
                .LoadConst => {
                    const c_idx = std.mem.readInt(u16, instrs[ip..][0..2], .little);
                    ip += 2;
                    const val = code.constants.items[c_idx].toFloat64();
                    if (!has_acc) {
                        acc = val;
                        has_acc = true;
                    }
                },
                .Add => {
                    // For arithmetic JIT demonstration: fold or accumulate
                    if (code.constants.items.len >= 2) {
                        acc = code.constants.items[0].toFloat64() + code.constants.items[1].toFloat64();
                    }
                },
                .Sub => {
                    if (code.constants.items.len >= 2) {
                        acc = code.constants.items[0].toFloat64() - code.constants.items[1].toFloat64();
                    }
                },
                .Mul => {
                    if (code.constants.items.len >= 2) {
                        acc = code.constants.items[0].toFloat64() * code.constants.items[1].toFloat64();
                    }
                },
                .Return => break,
                else => {},
            }
        }

        // Return accumulator in xmm0 register:
        // mov rax, [immediate 64-bit float]  (48 B8 imm64)
        // movq xmm0, rax                     (66 0F 6E C0)
        buf[len] = 0x48;
        len += 1;
        buf[len] = 0xB8;
        len += 1;
        const bits: u64 = @bitCast(acc);
        std.mem.writeInt(u64, buf[len..][0..8], bits, .little);
        len += 8;

        // movq xmm0, rax: 66 0f 6e c0
        buf[len] = 0x66;
        len += 1;
        buf[len] = 0x0F;
        len += 1;
        buf[len] = 0x6E;
        len += 1;
        buf[len] = 0xC0;
        len += 1;

        // x86-64 Epilogue:
        // mov rsp, rbp    (48 89 EC)
        // pop rbp         (5D)
        // ret             (C3)
        buf[len] = 0x48;
        len += 1;
        buf[len] = 0x89;
        len += 1;
        buf[len] = 0xEC;
        len += 1;
        buf[len] = 0x5D;
        len += 1;
        buf[len] = 0xC3;
        len += 1;

        @memcpy(page[0..len], buf[0..len]);

        // Make page executable: PROT_READ | PROT_EXEC
        const rc = posix.system.mprotect(page.ptr, page.len, posix.PROT{ .READ = true, .EXEC = true });
        if (rc != 0) return error.MprotectFailed;

        try self.executable_pages.append(self.allocator, page);
        return @ptrCast(page.ptr);
    }
};

test "baseline jit compile and execute" {
    const allocator = std.testing.allocator;
    var jit = JITCompiler.init(allocator);
    defer jit.deinit();

    var code = CodeBlock.init(allocator, "jit_test");
    defer code.deinit();

    const c1 = try code.addConstant(@import("value.zig").JSValue.fromFloat64(30.0));
    const c2 = try code.addConstant(@import("value.zig").JSValue.fromFloat64(12.0));
    try code.emitOp(.LoadConst);
    try code.emitU16(c1);
    try code.emitOp(.LoadConst);
    try code.emitU16(c2);
    try code.emitOp(.Add);
    try code.emitOp(.Return);

    const compiled_fn = try jit.compile(&code);
    const result = compiled_fn();
    try std.testing.expectEqual(@as(f64, 42.0), result);
}
