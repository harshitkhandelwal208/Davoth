//! High-performance 64-bit NaN-boxed JSValue representation.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;

pub const JSObject = @import("object.zig").JSObject;

pub const JSValueType = enum {
    Undefined,
    Null,
    Boolean,
    Int32,
    Float64,
    String,
    Symbol,
    Object,
};

pub const JSValue = packed struct(u64) {
    raw: u64,

    // IEEE 754 Quiet NaN + tag in high 16 bits
    const QNAN_MASK: u64 = 0x7FF8_0000_0000_0000;
    const TAG_MASK: u64 = 0xFFFF_0000_0000_0000;
    const PAYLOAD_MASK: u64 = 0x0000_FFFF_FFFF_FFFF;

    const TAG_UNDEFINED: u64 = 0xFFF9_0000_0000_0000;
    const TAG_NULL: u64 = 0xFFFA_0000_0000_0000;
    const TAG_BOOL: u64 = 0xFFFB_0000_0000_0000;
    const TAG_INT32: u64 = 0xFFFC_0000_0000_0000;
    const TAG_STRING: u64 = 0xFFFD_0000_0000_0000;
    const TAG_SYMBOL: u64 = 0xFFFE_0000_0000_0000;
    const TAG_OBJECT: u64 = 0xFFFF_0000_0000_0000;

    pub const undefined_val = JSValue{ .raw = TAG_UNDEFINED };
    pub const null_val = JSValue{ .raw = TAG_NULL };
    pub const true_val = JSValue{ .raw = TAG_BOOL | 1 };
    pub const false_val = JSValue{ .raw = TAG_BOOL | 0 };

    pub fn fromInt32(val: i32) JSValue {
        const uval: u32 = @bitCast(val);
        return .{ .raw = TAG_INT32 | @as(u64, uval) };
    }

    pub fn fromFloat64(val: f64) JSValue {
        const bits: u64 = @bitCast(val);
        // Canonicalize NaNs to prevent colliding with tagged values
        if ((bits & TAG_MASK) >= TAG_UNDEFINED) {
            return .{ .raw = QNAN_MASK };
        }
        return .{ .raw = bits };
    }

    pub fn fromBoolean(val: bool) JSValue {
        return if (val) true_val else false_val;
    }

    pub fn fromStringAtom(atom: AtomId) JSValue {
        return .{ .raw = TAG_STRING | @as(u64, atom.toU32()) };
    }

    pub fn fromObject(obj: *JSObject) JSValue {
        const ptr_int = @intFromPtr(obj);
        return .{ .raw = TAG_OBJECT | (ptr_int & PAYLOAD_MASK) };
    }

    pub fn getType(self: JSValue) JSValueType {
        const tag = self.raw & TAG_MASK;
        if (tag == TAG_UNDEFINED) return .Undefined;
        if (tag == TAG_NULL) return .Null;
        if (tag == TAG_BOOL) return .Boolean;
        if (tag == TAG_INT32) return .Int32;
        if (tag == TAG_STRING) return .String;
        if (tag == TAG_SYMBOL) return .Symbol;
        if (tag == TAG_OBJECT) return .Object;
        return .Float64;
    }

    pub fn isUndefined(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_UNDEFINED;
    }

    pub fn isNull(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_NULL;
    }

    pub fn isNullOrUndefined(self: JSValue) bool {
        const tag = self.raw & TAG_MASK;
        return tag == TAG_NULL or tag == TAG_UNDEFINED;
    }

    pub fn isBoolean(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_BOOL;
    }

    pub fn toBoolean(self: JSValue) bool {
        return switch (self.getType()) {
            .Boolean => (self.raw & 1) != 0,
            .Undefined, .Null => false,
            .Int32 => self.toInt32() != 0,
            .Float64 => self.toFloat64() != 0.0 and !std.math.isNan(self.toFloat64()),
            .String => (self.raw & 0xFFFF_FFFF) != 0,
            .Symbol, .Object => true,
        };
    }

    pub fn isInt32(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_INT32;
    }

    pub fn toInt32(self: JSValue) i32 {
        if (self.isInt32()) {
            const uval: u32 = @truncate(self.raw & 0xFFFF_FFFF);
            return @bitCast(uval);
        }
        if (self.getType() == .Float64) {
            return @intFromFloat(self.toFloat64());
        }
        if (self.isBoolean()) {
            return if (self.toBoolean()) 1 else 0;
        }
        return 0;
    }

    pub fn isFloat64(self: JSValue) bool {
        return self.getType() == .Float64;
    }

    pub fn toFloat64(self: JSValue) f64 {
        if (self.isInt32()) {
            return @floatFromInt(self.toInt32());
        }
        if (self.isFloat64()) {
            return @bitCast(self.raw);
        }
        if (self.isBoolean()) {
            return if (self.toBoolean()) 1.0 else 0.0;
        }
        return std.math.nan(f64);
    }

    pub fn isNumber(self: JSValue) bool {
        return self.isInt32() or self.isFloat64();
    }

    pub fn isString(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_STRING;
    }

    pub fn toStringAtom(self: JSValue) AtomId {
        const uval: u32 = @truncate(self.raw & 0xFFFF_FFFF);
        return AtomId.fromU32(uval);
    }

    pub fn isObject(self: JSValue) bool {
        return (self.raw & TAG_MASK) == TAG_OBJECT;
    }

    pub fn toObject(self: JSValue) ?*JSObject {
        if (!self.isObject()) return null;
        const ptr_int: usize = @intCast(self.raw & PAYLOAD_MASK);
        return @ptrFromInt(ptr_int);
    }
};

test "jsvalue nan tagging" {
    const val_und = JSValue.undefined_val;
    try std.testing.expect(val_und.isUndefined());
    try std.testing.expect(!val_und.toBoolean());

    const val_null = JSValue.null_val;
    try std.testing.expect(val_null.isNull());
    try std.testing.expect(val_null.isNullOrUndefined());

    const val_b = JSValue.fromBoolean(true);
    try std.testing.expect(val_b.isBoolean());
    try std.testing.expect(val_b.toBoolean());

    const val_i = JSValue.fromInt32(-12345);
    try std.testing.expect(val_i.isInt32());
    try std.testing.expectEqual(@as(i32, -12345), val_i.toInt32());

    const val_f = JSValue.fromFloat64(3.14159265);
    try std.testing.expect(val_f.isFloat64());
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159265), val_f.toFloat64(), 0.00001);

    const atom = AtomId.fromU32(77);
    const val_s = JSValue.fromStringAtom(atom);
    try std.testing.expect(val_s.isString());
    try std.testing.expectEqual(atom, val_s.toStringAtom());
}
