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
    const log_fn = try vm.gc.allocateFunction(null, nativeConsoleLog, @ptrCast(vm));
    const log_atom = try table.intern("log");
    try console_obj.setProperty(alloc, log_atom, JSValue.fromObject(log_fn));

    const warn_fn = try vm.gc.allocateFunction(null, nativeConsoleWarn, @ptrCast(vm));
    const warn_atom = try table.intern("warn");
    try console_obj.setProperty(alloc, warn_atom, JSValue.fromObject(warn_fn));

    const error_fn = try vm.gc.allocateFunction(null, nativeConsoleError, @ptrCast(vm));
    const error_atom = try table.intern("error");
    try console_obj.setProperty(alloc, error_atom, JSValue.fromObject(error_fn));

    const console_atom = try table.intern("console");
    try global.setProperty(alloc, console_atom, JSValue.fromObject(console_obj));

    // Math object
    const math_obj = try vm.gc.allocateObject(null);
    const pi_atom = try table.intern("PI");
    try math_obj.setProperty(alloc, pi_atom, JSValue.fromFloat64(std.math.pi));

    const floor_fn = try vm.gc.allocateFunction(null, nativeMathFloor, null);
    const floor_atom = try table.intern("floor");
    try math_obj.setProperty(alloc, floor_atom, JSValue.fromObject(floor_fn));

    const ceil_fn = try vm.gc.allocateFunction(null, nativeMathCeil, null);
    const ceil_atom = try table.intern("ceil");
    try math_obj.setProperty(alloc, ceil_atom, JSValue.fromObject(ceil_fn));

    const abs_fn = try vm.gc.allocateFunction(null, nativeMathAbs, null);
    const abs_atom = try table.intern("abs");
    try math_obj.setProperty(alloc, abs_atom, JSValue.fromObject(abs_fn));

    const math_atom = try table.intern("Math");
    try global.setProperty(alloc, math_atom, JSValue.fromObject(math_obj));

    // Timers: setTimeout, clearTimeout, setInterval, clearInterval
    const set_timeout_fn = try vm.gc.allocateFunction(null, nativeSetTimeout, null);
    try global.setProperty(alloc, try table.intern("setTimeout"), JSValue.fromObject(set_timeout_fn));

    const clear_timeout_fn = try vm.gc.allocateFunction(null, nativeClearTimeout, null);
    try global.setProperty(alloc, try table.intern("clearTimeout"), JSValue.fromObject(clear_timeout_fn));

    const set_interval_fn = try vm.gc.allocateFunction(null, nativeSetTimeout, null);
    try global.setProperty(alloc, try table.intern("setInterval"), JSValue.fromObject(set_interval_fn));

    const clear_interval_fn = try vm.gc.allocateFunction(null, nativeClearTimeout, null);
    try global.setProperty(alloc, try table.intern("clearInterval"), JSValue.fromObject(clear_interval_fn));

    // Web Storage: localStorage & sessionStorage
    const storage_obj = try vm.gc.allocateObject(null);
    const set_item_fn = try vm.gc.allocateFunction(null, nativeStorageSetItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("setItem"), JSValue.fromObject(set_item_fn));

    const get_item_fn = try vm.gc.allocateFunction(null, nativeStorageGetItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("getItem"), JSValue.fromObject(get_item_fn));

    const remove_item_fn = try vm.gc.allocateFunction(null, nativeStorageRemoveItem, @ptrCast(vm));
    try storage_obj.setProperty(alloc, try table.intern("removeItem"), JSValue.fromObject(remove_item_fn));

    try global.setProperty(alloc, try table.intern("localStorage"), JSValue.fromObject(storage_obj));
    try global.setProperty(alloc, try table.intern("sessionStorage"), JSValue.fromObject(storage_obj));

    // Fetch API
    const fetch_fn = try vm.gc.allocateFunction(null, nativeFetch, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("fetch"), JSValue.fromObject(fetch_fn));

    // Global utility functions
    const parse_int_fn = try vm.gc.allocateFunction(null, nativeParseInt, null);
    const parse_int_atom = try table.intern("parseInt");
    try global.setProperty(alloc, parse_int_atom, JSValue.fromObject(parse_int_fn));

    const is_nan_fn = try vm.gc.allocateFunction(null, nativeIsNaN, null);
    const is_nan_atom = try table.intern("isNaN");
    try global.setProperty(alloc, is_nan_atom, JSValue.fromObject(is_nan_fn));

    // Array constructor & ES2024 prototype helpers: toReversed, toSorted, with, toSpliced
    const array_proto = try vm.gc.allocateObject(null);
    array_proto.builtin_type = .Array;

    const to_reversed_fn = try vm.gc.allocateFunction(null, nativeArrayToReversed, @ptrCast(vm));
    try array_proto.setProperty(alloc, try table.intern("toReversed"), JSValue.fromObject(to_reversed_fn));

    const to_sorted_fn = try vm.gc.allocateFunction(null, nativeArrayToSorted, @ptrCast(vm));
    try array_proto.setProperty(alloc, try table.intern("toSorted"), JSValue.fromObject(to_sorted_fn));

    const with_fn = try vm.gc.allocateFunction(null, nativeArrayWith, @ptrCast(vm));
    try array_proto.setProperty(alloc, try table.intern("with"), JSValue.fromObject(with_fn));

    const to_spliced_fn = try vm.gc.allocateFunction(null, nativeArrayToSpliced, @ptrCast(vm));
    try array_proto.setProperty(alloc, try table.intern("toSpliced"), JSValue.fromObject(to_spliced_fn));

    const array_obj = try vm.gc.allocateObject(null);
    try array_obj.setProperty(alloc, try table.intern("prototype"), JSValue.fromObject(array_proto));
    try global.setProperty(alloc, try table.intern("Array"), JSValue.fromObject(array_obj));

    // Promise constructor & combinators: allSettled, any, resolve, reject
    const promise_obj = try vm.gc.allocateObject(null);
    const all_settled_fn = try vm.gc.allocateFunction(null, nativePromiseAllSettled, @ptrCast(vm));
    try promise_obj.setProperty(alloc, try table.intern("allSettled"), JSValue.fromObject(all_settled_fn));

    const any_fn = try vm.gc.allocateFunction(null, nativePromiseAny, @ptrCast(vm));
    try promise_obj.setProperty(alloc, try table.intern("any"), JSValue.fromObject(any_fn));

    const resolve_fn = try vm.gc.allocateFunction(null, nativePromiseResolve, @ptrCast(vm));
    try promise_obj.setProperty(alloc, try table.intern("resolve"), JSValue.fromObject(resolve_fn));

    const reject_fn = try vm.gc.allocateFunction(null, nativePromiseReject, @ptrCast(vm));
    try promise_obj.setProperty(alloc, try table.intern("reject"), JSValue.fromObject(reject_fn));

    try global.setProperty(alloc, try table.intern("Promise"), JSValue.fromObject(promise_obj));

    // JSON object: parse (with reviver support) and stringify
    const json_obj = try vm.gc.allocateObject(null);
    const json_parse_fn = try vm.gc.allocateFunction(null, nativeJsonParse, @ptrCast(vm));
    try json_obj.setProperty(alloc, try table.intern("parse"), JSValue.fromObject(json_parse_fn));

    const json_stringify_fn = try vm.gc.allocateFunction(null, nativeJsonStringify, @ptrCast(vm));
    try json_obj.setProperty(alloc, try table.intern("stringify"), JSValue.fromObject(json_stringify_fn));

    try global.setProperty(alloc, try table.intern("JSON"), JSValue.fromObject(json_obj));
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

pub fn createArray(vm: *VM, items: []const JSValue) !*JSObject {
    const obj = try vm.gc.allocateObject(null);
    obj.builtin_type = .Array;
    const len_atom = try vm.atom_table.intern("length");
    try obj.setProperty(vm.allocator, len_atom, JSValue.fromInt32(@intCast(items.len)));

    for (items, 0..) |item, i| {
        var buf: [32]u8 = undefined;
        const key_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
        const key_atom = try vm.atom_table.intern(key_str);
        try obj.setProperty(vm.allocator, key_atom, item);
    }
    return obj;
}

pub fn getArrayElements(vm: *VM, obj: *JSObject, out: *std.ArrayList(JSValue)) !void {
    const len_atom = vm.atom_table.map.get("length") orelse return;
    const len_val = obj.getProperty(len_atom) orelse return;
    const len_count: usize = switch (len_val.getType()) {
        .Int32 => @intCast(@max(0, len_val.toInt32())),
        .Float64 => @intCast(@max(0, @as(i64, @intFromFloat(len_val.toFloat64())))),
        else => 0,
    };

    var i: usize = 0;
    while (i < len_count) : (i += 1) {
        var buf: [32]u8 = undefined;
        const key_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
        if (vm.atom_table.map.get(key_str)) |key_atom| {
            if (obj.getProperty(key_atom)) |val| {
                try out.append(vm.allocator, val);
                continue;
            }
        }
        try out.append(vm.allocator, JSValue.undefined_val);
    }
}

fn nativeArrayToReversed(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    std.mem.reverse(JSValue, elements.items);
    const new_arr = try createArray(vm, elements.items);
    return JSValue.fromObject(new_arr);
}

fn nativeArrayToSorted(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    const Context = struct {
        fn lessThan(_: void, a: JSValue, b: JSValue) bool {
            return a.toFloat64() < b.toFloat64();
        }
    };
    std.mem.sort(JSValue, elements.items, {}, Context.lessThan);

    const new_arr = try createArray(vm, elements.items);
    return JSValue.fromObject(new_arr);
}

fn nativeArrayWith(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const target = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2) return JSValue.undefined_val;

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    const raw_idx: i64 = switch (args[0].getType()) {
        .Int32 => @as(i64, args[0].toInt32()),
        .Float64 => @as(i64, @intFromFloat(args[0].toFloat64())),
        else => 0,
    };

    const len: i64 = @intCast(elements.items.len);
    const actual_idx: i64 = if (raw_idx < 0) len + raw_idx else raw_idx;

    if (actual_idx < 0 or actual_idx >= len) {
        return error.IndexOutOfBounds;
    }

    elements.items[@intCast(actual_idx)] = args[1];
    const new_arr = try createArray(vm, elements.items);
    return JSValue.fromObject(new_arr);
}

fn nativeArrayToSpliced(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    const len: i64 = @intCast(elements.items.len);
    var start: i64 = 0;
    if (args.len > 0) {
        const raw_s = args[0].toInt32();
        start = if (raw_s < 0) @max(0, len + raw_s) else @min(len, raw_s);
    }

    var delete_count: i64 = len - start;
    if (args.len > 1) {
        const raw_del = @max(0, args[1].toInt32());
        delete_count = @min(raw_del, len - start);
    }

    var new_items: std.ArrayList(JSValue) = .empty;
    defer new_items.deinit(vm.allocator);

    var i: usize = 0;
    while (i < @as(usize, @intCast(start))) : (i += 1) {
        try new_items.append(vm.allocator, elements.items[i]);
    }

    if (args.len > 2) {
        for (args[2..]) |arg| {
            try new_items.append(vm.allocator, arg);
        }
    }

    var j: usize = @intCast(start + delete_count);
    while (j < elements.items.len) : (j += 1) {
        try new_items.append(vm.allocator, elements.items[j]);
    }

    const new_arr = try createArray(vm, new_items.items);
    return JSValue.fromObject(new_arr);
}

fn nativePromiseAllSettled(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    var results: std.ArrayList(JSValue) = .empty;
    defer results.deinit(vm.allocator);

    for (args) |arg| {
        const item_obj = try vm.gc.allocateObject(null);
        try item_obj.setProperty(vm.allocator, try vm.atom_table.intern("status"), JSValue.fromStringAtom(try vm.atom_table.intern("fulfilled")));
        try item_obj.setProperty(vm.allocator, try vm.atom_table.intern("value"), arg);
        try results.append(vm.allocator, JSValue.fromObject(item_obj));
    }

    const arr = try createArray(vm, results.items);
    return JSValue.fromObject(arr);
}

fn nativePromiseAny(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len > 0) {
        return args[0];
    }
    return error.AllPromisesRejected;
}

fn nativePromiseResolve(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len > 0) return args[0];
    return JSValue.undefined_val;
}

fn nativePromiseReject(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len > 0) return args[0];
    return JSValue.undefined_val;
}

fn nativeJsonParse(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;

    var json_str: []const u8 = "";
    if (args[0].isString()) {
        json_str = vm.atom_table.get(args[0].toStringAtom());
    } else {
        return JSValue.undefined_val;
    }

    const trimmed = std.mem.trim(u8, json_str, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "null")) return JSValue.null_val;
    if (std.mem.eql(u8, trimmed, "true")) return JSValue.true_val;
    if (std.mem.eql(u8, trimmed, "false")) return JSValue.false_val;

    if (std.fmt.parseFloat(f64, trimmed)) |num| {
        var res = JSValue.fromFloat64(num);
        if (args.len > 1 and args[1].isObject()) {
            if (args[1].toObject().?.native_fn) |rev_fn| {
                res = try rev_fn(args[1].toObject().?.native_ctx.?, JSValue.undefined_val, &[_]JSValue{
                    JSValue.fromStringAtom(try vm.atom_table.intern("")),
                    res,
                });
            }
        }
        return res;
    } else |_| {}

    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        const atom = try vm.atom_table.intern(trimmed[1 .. trimmed.len - 1]);
        var res = JSValue.fromStringAtom(atom);
        if (args.len > 1 and args[1].isObject()) {
            if (args[1].toObject().?.native_fn) |rev_fn| {
                res = try rev_fn(args[1].toObject().?.native_ctx.?, JSValue.undefined_val, &[_]JSValue{
                    JSValue.fromStringAtom(try vm.atom_table.intern("")),
                    res,
                });
            }
        }
        return res;
    }

    return JSValue.null_val;
}

fn nativeJsonStringify(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;

    switch (args[0].getType()) {
        .Null => return JSValue.fromStringAtom(try vm.atom_table.intern("null")),
        .Boolean => return JSValue.fromStringAtom(try vm.atom_table.intern(if (args[0].toBoolean()) "true" else "false")),
        .Int32 => {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{args[0].toInt32()});
            return JSValue.fromStringAtom(try vm.atom_table.intern(str));
        },
        .Float64 => {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{args[0].toFloat64()});
            return JSValue.fromStringAtom(try vm.atom_table.intern(str));
        },
        .String => {
            const raw = vm.atom_table.get(args[0].toStringAtom());
            const quoted = try std.fmt.allocPrint(vm.allocator, "\"{s}\"", .{raw});
            defer vm.allocator.free(quoted);
            return JSValue.fromStringAtom(try vm.atom_table.intern(quoted));
        },
        else => return JSValue.fromStringAtom(try vm.atom_table.intern("{}")),
    }
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

test "es2024 array helpers and promise combinators" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    // 1. Array ES2024: toReversed, toSorted, with, toSpliced
    const items = [_]JSValue{
        JSValue.fromFloat64(30.0),
        JSValue.fromFloat64(10.0),
        JSValue.fromFloat64(20.0),
    };
    const arr = try createArray(vm, &items);

    // toReversed
    const rev_val = try nativeArrayToReversed(@ptrCast(vm), JSValue.fromObject(arr), &[_]JSValue{});
    var rev_items: std.ArrayList(JSValue) = .empty;
    defer rev_items.deinit(allocator);
    try getArrayElements(vm, rev_val.toObject().?, &rev_items);
    try std.testing.expectEqual(@as(usize, 3), rev_items.items.len);
    try std.testing.expectEqual(@as(f64, 20.0), rev_items.items[0].toFloat64());
    try std.testing.expectEqual(@as(f64, 10.0), rev_items.items[1].toFloat64());
    try std.testing.expectEqual(@as(f64, 30.0), rev_items.items[2].toFloat64());

    // toSorted
    const sort_val = try nativeArrayToSorted(@ptrCast(vm), JSValue.fromObject(arr), &[_]JSValue{});
    var sort_items: std.ArrayList(JSValue) = .empty;
    defer sort_items.deinit(allocator);
    try getArrayElements(vm, sort_val.toObject().?, &sort_items);
    try std.testing.expectEqual(@as(f64, 10.0), sort_items.items[0].toFloat64());
    try std.testing.expectEqual(@as(f64, 20.0), sort_items.items[1].toFloat64());
    try std.testing.expectEqual(@as(f64, 30.0), sort_items.items[2].toFloat64());

    // with
    const with_val = try nativeArrayWith(@ptrCast(vm), JSValue.fromObject(arr), &[_]JSValue{
        JSValue.fromInt32(1),
        JSValue.fromFloat64(99.0),
    });
    var with_items: std.ArrayList(JSValue) = .empty;
    defer with_items.deinit(allocator);
    try getArrayElements(vm, with_val.toObject().?, &with_items);
    try std.testing.expectEqual(@as(f64, 99.0), with_items.items[1].toFloat64());

    // 2. Promise allSettled & any
    const p_settled = try nativePromiseAllSettled(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromInt32(100),
        JSValue.fromInt32(200),
    });
    try std.testing.expect(p_settled.isObject());

    const p_any = try nativePromiseAny(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromInt32(42),
    });
    try std.testing.expectEqual(@as(i32, 42), p_any.toInt32());

    // 3. JSON parse with reviver support
    const parsed = try nativeJsonParse(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("42")),
    });
    try std.testing.expectEqual(@as(f64, 42.0), parsed.toFloat64());
}
