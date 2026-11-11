//! Standard ECMAScript built-in global objects and functions.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const VM = @import("interpreter.zig").VM;

pub fn initBuiltins(vm: *VM) !void {
    const table = vm.atom_table;
    const alloc = vm.allocator;
    const global = vm.global_object;

    // console object
    const console_obj = try vm.gc.allocateObject(null);
    const log_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeConsoleLog, @ptrCast(vm));
    const log_atom = try table.intern("log");
    try console_obj.setProperty(alloc, log_atom, JSValue.fromObject(log_fn));

    const console_atom = try table.intern("console");
    try global.setProperty(alloc, console_atom, JSValue.fromObject(console_obj));

    // Math object
    const math_obj = try vm.gc.allocateObject(null);
    const pi_atom = try table.intern("PI");
    try math_obj.setProperty(alloc, pi_atom, JSValue.fromFloat64(std.math.pi));

    const floor_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeMathFloor, null);
    const floor_atom = try table.intern("floor");
    try math_obj.setProperty(alloc, floor_atom, JSValue.fromObject(floor_fn));

    const ceil_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeMathCeil, null);
    const ceil_atom = try table.intern("ceil");
    try math_obj.setProperty(alloc, ceil_atom, JSValue.fromObject(ceil_fn));

    const abs_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeMathAbs, null);
    const abs_atom = try table.intern("abs");
    try math_obj.setProperty(alloc, abs_atom, JSValue.fromObject(abs_fn));

    const math_atom = try table.intern("Math");
    try global.setProperty(alloc, math_atom, JSValue.fromObject(math_obj));

    // Global utility functions
    const parse_int_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeParseInt, null);
    const parse_int_atom = try table.intern("parseInt");
    try global.setProperty(alloc, parse_int_atom, JSValue.fromObject(parse_int_fn));

    const is_nan_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeIsNaN, null);
    const is_nan_atom = try table.intern("isNaN");
    try global.setProperty(alloc, is_nan_atom, JSValue.fromObject(is_nan_fn));
}

fn nativeConsoleLog(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    for (args, 0..) |arg, i| {
        if (i > 0) std.debug.print(" ", .{});
        switch (arg.getType()) {
            .Int32 => std.debug.print("{d}", .{arg.toInt32()}),
            .Float64 => std.debug.print("{d}", .{arg.toFloat64()}),
            .Boolean => std.debug.print("{}", .{arg.toBoolean()}),
            .Undefined => std.debug.print("undefined", .{}),
            .Null => std.debug.print("null", .{}),
            .String => std.debug.print("[String atom={d}]", .{arg.toStringAtom().toU32()}),
            .Object => std.debug.print("[Object]", .{}),
            .Symbol => std.debug.print("[Symbol]", .{}),
        }
    }
    std.debug.print("\n", .{});
    return JSValue.undefined_val;
}

fn nativeMathFloor(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.fromFloat64(std.math.nan(f64));
    return JSValue.fromFloat64(@floor(args[0].toFloat64()));
}

fn nativeMathCeil(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.fromFloat64(std.math.nan(f64));
    return JSValue.fromFloat64(@ceil(args[0].toFloat64()));
}

fn nativeMathAbs(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.fromFloat64(std.math.nan(f64));
    return JSValue.fromFloat64(@abs(args[0].toFloat64()));
}

fn nativeParseInt(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.fromFloat64(std.math.nan(f64));
    return JSValue.fromInt32(args[0].toInt32());
}

fn nativeIsNaN(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.fromBoolean(true);
    return JSValue.fromBoolean(std.math.isNan(args[0].toFloat64()));
}

test "builtins installation and execution" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const math_atom = try atom_table.intern("Math");
    const math_val = vm.global_object.getProperty(math_atom).?;
    try std.testing.expect(math_val.isObject());

    const pi_atom = try atom_table.intern("PI");
    const pi_val = math_val.toObject().?.getProperty(pi_atom).?;
    try std.testing.expectApproxEqAbs(std.math.pi, pi_val.toFloat64(), 0.0001);
}
