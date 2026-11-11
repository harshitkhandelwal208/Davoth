//! Standard ECMAScript built-in global objects and functions.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const VM = @import("interpreter.zig").VM;

var timer_counter: i32 = 1;

pub fn initBuiltins(vm: *VM) !void {
    const table = vm.atom_table;
    const alloc = vm.allocator;
    const global = vm.global_object;

    // window and globalThis self-references
    const window_atom = try table.intern("window");
    try global.setProperty(alloc, window_atom, JSValue.fromObject(global));

    const global_this_atom = try table.intern("globalThis");
    try global.setProperty(alloc, global_this_atom, JSValue.fromObject(global));

    // console object
    const console_obj = try vm.gc.allocateObject(null);
    const log_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeConsoleLog, @ptrCast(vm));
    const log_atom = try table.intern("log");
    try console_obj.setProperty(alloc, log_atom, JSValue.fromObject(log_fn));

    const warn_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeConsoleWarn, @ptrCast(vm));
    const warn_atom = try table.intern("warn");
    try console_obj.setProperty(alloc, warn_atom, JSValue.fromObject(warn_fn));

    const error_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeConsoleError, @ptrCast(vm));
    const error_atom = try table.intern("error");
    try console_obj.setProperty(alloc, error_atom, JSValue.fromObject(error_fn));

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

    // Timers: setTimeout, clearTimeout, setInterval, clearInterval
    const set_timeout_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeSetTimeout, null);
    try global.setProperty(alloc, try table.intern("setTimeout"), JSValue.fromObject(set_timeout_fn));

    const clear_timeout_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeClearTimeout, null);
    try global.setProperty(alloc, try table.intern("clearTimeout"), JSValue.fromObject(clear_timeout_fn));

    const set_interval_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeSetTimeout, null);
    try global.setProperty(alloc, try table.intern("setInterval"), JSValue.fromObject(set_interval_fn));

    const clear_interval_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeClearTimeout, null);
    try global.setProperty(alloc, try table.intern("clearInterval"), JSValue.fromObject(clear_interval_fn));

    // Web Storage: localStorage & sessionStorage
    const storage_obj = try vm.gc.allocateObject(null);
    const set_item_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeStorageSetItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("setItem"), JSValue.fromObject(set_item_fn));

    const get_item_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeStorageGetItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("getItem"), JSValue.fromObject(get_item_fn));

    const remove_item_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeStorageRemoveItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("removeItem"), JSValue.fromObject(remove_item_fn));

    try global.setProperty(alloc, try table.intern("localStorage"), JSValue.fromObject(storage_obj));
    try global.setProperty(alloc, try table.intern("sessionStorage"), JSValue.fromObject(storage_obj));

    // Fetch API
    const fetch_fn = try JSObject.createFunction(alloc, vm.gc.root_shape, null, nativeFetch, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("fetch"), JSValue.fromObject(fetch_fn));

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

fn nativeConsoleWarn(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    return nativeConsoleLog(ctx, this_val, args);
}

fn nativeConsoleError(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    return nativeConsoleLog(ctx, this_val, args);
}

fn nativeSetTimeout(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const id = timer_counter;
    timer_counter += 1;
    return JSValue.fromInt32(id);
}

fn nativeClearTimeout(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeStorageSetItem(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len < 2) return JSValue.undefined_val;
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    var key_buf: [128]u8 = undefined;
    const key_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&key_buf, "{d}", .{args[0].toInt32()}) catch "0",
        else => "key",
    };
    const key_atom = try vm.atom_table.intern(key_str);
    try target.setProperty(vm.allocator, key_atom, args[1]);
    return JSValue.undefined_val;
}

fn nativeStorageGetItem(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.null_val;
    const target = this_val.toObject() orelse return JSValue.null_val;

    var key_buf: [128]u8 = undefined;
    const key_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&key_buf, "{d}", .{args[0].toInt32()}) catch "0",
        else => "key",
    };
    const key_atom = vm.atom_table.map.get(key_str) orelse return JSValue.null_val;
    return target.getProperty(key_atom) orelse JSValue.null_val;
}

fn nativeStorageRemoveItem(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    const key_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };
    const key_atom = vm.atom_table.map.get(key_str) orelse return JSValue.undefined_val;
    try target.setProperty(vm.allocator, key_atom, JSValue.null_val);
    return JSValue.undefined_val;
}

fn nativeFetch(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const resp_obj = try vm.gc.allocateObject(null);
    try resp_obj.setProperty(vm.allocator, try vm.atom_table.intern("status"), JSValue.fromInt32(200));
    try resp_obj.setProperty(vm.allocator, try vm.atom_table.intern("ok"), JSValue.true_val);

    const ok_atom = try vm.atom_table.intern("OK");
    try resp_obj.setProperty(vm.allocator, try vm.atom_table.intern("statusText"), JSValue.fromStringAtom(ok_atom));
    return JSValue.fromObject(resp_obj);
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

    // Verify window and globalThis
    const win_val = vm.global_object.getProperty(try atom_table.intern("window")).?;
    try std.testing.expect(win_val.isObject());
    try std.testing.expectEqual(vm.global_object, win_val.toObject().?);

    const math_atom = try atom_table.intern("Math");
    const math_val = vm.global_object.getProperty(math_atom).?;
    try std.testing.expect(math_val.isObject());

    const pi_atom = try atom_table.intern("PI");
    const pi_val = math_val.toObject().?.getProperty(pi_atom).?;
    try std.testing.expectApproxEqAbs(std.math.pi, pi_val.toFloat64(), 0.0001);

    // Verify localStorage set and get
    const storage_atom = try atom_table.intern("localStorage");
    const storage_val = vm.global_object.getProperty(storage_atom).?;
    const storage_obj = storage_val.toObject().?;

    const set_item_fn = storage_obj.getProperty(try atom_table.intern("setItem")).?.toObject().?;
    const get_item_fn = storage_obj.getProperty(try atom_table.intern("getItem")).?.toObject().?;

    const key_atom = try atom_table.intern("username");
    const val_atom = try atom_table.intern("DavothUser");

    _ = try set_item_fn.native_fn.?(set_item_fn.native_ctx.?, storage_val, &[_]JSValue{
        JSValue.fromStringAtom(key_atom),
        JSValue.fromStringAtom(val_atom),
    });

    const retrieved = try get_item_fn.native_fn.?(get_item_fn.native_ctx.?, storage_val, &[_]JSValue{
        JSValue.fromStringAtom(key_atom),
    });
    try std.testing.expect(retrieved.isString());
    try std.testing.expectEqual(val_atom, retrieved.toStringAtom());
}
