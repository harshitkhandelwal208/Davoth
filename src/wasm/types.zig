//! WebAssembly types and values.
const std = @import("std");

pub const ValueType = enum(u8) {
    I32 = 0x7F,
    I64 = 0x7E,
    F32 = 0x7D,
    F64 = 0x7C,
};

pub const Limits = struct {
    min: u32,
    max: ?u32 = null,
};

pub const FuncType = struct {
    params: []ValueType,
    returns: []ValueType,
};

pub const WasmValue = union(ValueType) {
    I32: i32,
    I64: i64,
    F32: f32,
    F64: f64,

    pub fn toI32(self: WasmValue) i32 {
        return switch (self) {
            .I32 => |v| v,
            else => 0,
        };
    }

    pub fn toI64(self: WasmValue) i64 {
        return switch (self) {
            .I64 => |v| v,
            else => 0,
        };
    }
};
