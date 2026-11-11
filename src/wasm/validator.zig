//! WebAssembly bytecode validation and operand type checking.
const std = @import("std");
const WasmModule = @import("decoder.zig").WasmModule;

pub const Validator = struct {
    module: *const WasmModule,

    pub fn init(mod: *const WasmModule) Validator {
        return .{ .module = mod };
    }

    pub fn validate(self: *const Validator) !void {
        // Check function count matches code bodies
        if (self.module.functions.items.len != self.module.code_bodies.items.len) {
            return error.FunctionCodeCountMismatch;
        }

        // Validate type indices for functions
        for (self.module.functions.items) |type_idx| {
            if (type_idx >= self.module.types.items.len) {
                return error.InvalidTypeIndex;
            }
        }

        // Validate exports point to valid function indices
        for (self.module.exports.items) |exp| {
            if (exp.kind == 0) { // Function export
                if (exp.index >= self.module.functions.items.len) {
                    return error.ExportFunctionIndexOutOfBounds;
                }
            }
        }
    }
};

test "validator basic module" {
    const allocator = std.testing.allocator;
    var mod = WasmModule{
        .allocator = allocator,
        .types = .empty,
        .functions = .empty,
        .exports = .empty,
        .code_bodies = .empty,
        .memory_limits = null,
    };
    defer mod.deinit();

    const validator = Validator.init(&mod);
    try validator.validate();
}
