//! Standard ECMAScript built-in global objects and functions.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const VM = @import("interpreter.zig").VM;
const c = @import("../common/c.zig");

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

    // Object constructor & helpers: groupBy, keys, values, assign
    const object_obj = try vm.gc.allocateObject(null);
    const group_by_fn = try vm.gc.allocateFunction(null, nativeObjectGroupBy, @ptrCast(vm));
    try object_obj.setProperty(alloc, try table.intern("groupBy"), JSValue.fromObject(group_by_fn));

    const keys_fn = try vm.gc.allocateFunction(null, nativeObjectKeys, @ptrCast(vm));
    try object_obj.setProperty(alloc, try table.intern("keys"), JSValue.fromObject(keys_fn));

    const values_fn = try vm.gc.allocateFunction(null, nativeObjectValues, @ptrCast(vm));
    try object_obj.setProperty(alloc, try table.intern("values"), JSValue.fromObject(values_fn));

    const assign_fn = try vm.gc.allocateFunction(null, nativeObjectAssign, @ptrCast(vm));
    try object_obj.setProperty(alloc, try table.intern("assign"), JSValue.fromObject(assign_fn));

    try global.setProperty(alloc, try table.intern("Object"), JSValue.fromObject(object_obj));

    // Promise.withResolvers (ES2024)
    const with_resolvers_fn = try vm.gc.allocateFunction(null, nativePromiseWithResolvers, @ptrCast(vm));
    try promise_obj.setProperty(alloc, try table.intern("withResolvers"), JSValue.fromObject(with_resolvers_fn));

    // crypto: randomUUID, getRandomValues
    const crypto_obj = try vm.gc.allocateObject(null);
    const uuid_fn = try vm.gc.allocateFunction(null, nativeCryptoRandomUUID, @ptrCast(vm));
    try crypto_obj.setProperty(alloc, try table.intern("randomUUID"), JSValue.fromObject(uuid_fn));

    const rand_values_fn = try vm.gc.allocateFunction(null, nativeCryptoGetRandomValues, @ptrCast(vm));
    try crypto_obj.setProperty(alloc, try table.intern("getRandomValues"), JSValue.fromObject(rand_values_fn));

    try global.setProperty(alloc, try table.intern("crypto"), JSValue.fromObject(crypto_obj));

    // Base64 encoding/decoding: btoa & atob
    const btoa_fn = try vm.gc.allocateFunction(null, nativeBtoa, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("btoa"), JSValue.fromObject(btoa_fn));

    const atob_fn = try vm.gc.allocateFunction(null, nativeAtob, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("atob"), JSValue.fromObject(atob_fn));

    // structuredClone deep copy Web API
    const clone_fn = try vm.gc.allocateFunction(null, nativeStructuredClone, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("structuredClone"), JSValue.fromObject(clone_fn));

    // queueMicrotask Web API
    const qm_fn = try vm.gc.allocateFunction(null, nativeQueueMicrotask, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("queueMicrotask"), JSValue.fromObject(qm_fn));

    // TextEncoder & TextDecoder Web APIs
    const text_encoder_fn = try vm.gc.allocateFunction(null, nativeTextEncoderConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("TextEncoder"), JSValue.fromObject(text_encoder_fn));

    const text_decoder_fn = try vm.gc.allocateFunction(null, nativeTextDecoderConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("TextDecoder"), JSValue.fromObject(text_decoder_fn));
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

fn nativeObjectGroupBy(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len < 2) return JSValue.undefined_val;
    const items_obj = args[0].toObject() orelse return JSValue.undefined_val;
    const callback_obj = args[1].toObject() orelse return JSValue.undefined_val;
    const cb_fn = callback_obj.native_fn orelse return JSValue.undefined_val;

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, items_obj, &elements);

    const out_groups = try vm.gc.allocateObject(null);

    var map = std.StringHashMap(std.ArrayList(JSValue)).init(vm.allocator);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(vm.allocator);
            vm.allocator.free(entry.key_ptr.*);
        }
        map.deinit();
    }

    for (elements.items, 0..) |elem, idx| {
        const key_val = try cb_fn(callback_obj.native_ctx orelse @ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
            elem,
            JSValue.fromInt32(@intCast(idx)),
        });

        var key_buf: [128]u8 = undefined;
        const key_str = switch (key_val.getType()) {
            .String => vm.atom_table.get(key_val.toStringAtom()),
            .Int32 => std.fmt.bufPrint(&key_buf, "{d}", .{key_val.toInt32()}) catch "0",
            else => "key",
        };

        const gop = try map.getOrPut(key_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try vm.allocator.dupe(u8, key_str);
            gop.value_ptr.* = .empty;
        }
        try gop.value_ptr.append(vm.allocator, elem);
    }

    var it = map.iterator();
    while (it.next()) |entry| {
        const group_arr = try createArray(vm, entry.value_ptr.items);
        const atom = try vm.atom_table.intern(entry.key_ptr.*);
        try out_groups.setProperty(vm.allocator, atom, JSValue.fromObject(group_arr));
    }

    return JSValue.fromObject(out_groups);
}

fn nativeObjectKeys(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));
    const target = args[0].toObject() orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));

    var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
    defer entries.deinit(vm.allocator);
    try target.getPropertyEntries(vm.allocator, &entries);

    var keys: std.ArrayList(JSValue) = .empty;
    defer keys.deinit(vm.allocator);

    for (entries.items) |prop| {
        const str = vm.atom_table.get(prop.atom);
        const key_atom = try vm.atom_table.intern(str);
        try keys.append(vm.allocator, JSValue.fromStringAtom(key_atom));
    }

    const arr = try createArray(vm, keys.items);
    return JSValue.fromObject(arr);
}

fn nativeObjectValues(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));
    const target = args[0].toObject() orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));

    var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
    defer entries.deinit(vm.allocator);
    try target.getPropertyEntries(vm.allocator, &entries);

    var vals: std.ArrayList(JSValue) = .empty;
    defer vals.deinit(vm.allocator);

    for (entries.items) |prop| {
        try vals.append(vm.allocator, prop.value);
    }

    const arr = try createArray(vm, vals.items);
    return JSValue.fromObject(arr);
}

fn nativeObjectAssign(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const target = args[0].toObject() orelse return args[0];

    for (args[1..]) |src_val| {
        if (src_val.toObject()) |src_obj| {
            var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
            defer entries.deinit(vm.allocator);
            try src_obj.getPropertyEntries(vm.allocator, &entries);

            for (entries.items) |prop| {
                try target.setProperty(vm.allocator, prop.atom, prop.value);
            }
        }
    }
    return args[0];
}

fn nativePromiseWithResolvers(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const res_obj = try vm.gc.allocateObject(null);
    const p_obj = try vm.gc.allocateObject(null);
    p_obj.builtin_type = .Promise;

    const res_fn = try vm.gc.allocateFunction(null, nativePromiseResolve, @ptrCast(vm));
    const rej_fn = try vm.gc.allocateFunction(null, nativePromiseReject, @ptrCast(vm));

    try res_obj.setProperty(vm.allocator, try vm.atom_table.intern("promise"), JSValue.fromObject(p_obj));
    try res_obj.setProperty(vm.allocator, try vm.atom_table.intern("resolve"), JSValue.fromObject(res_fn));
    try res_obj.setProperty(vm.allocator, try vm.atom_table.intern("reject"), JSValue.fromObject(rej_fn));

    return JSValue.fromObject(res_obj);
}

fn nativeCryptoRandomUUID(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    var bytes: [16]u8 = undefined;
    _ = c.RAND_bytes(&bytes, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // RFC 4122 version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

    var buf: [36]u8 = undefined;
    const uuid_str = try std.fmt.bufPrint(&buf, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
    });
    const atom = try vm.atom_table.intern(uuid_str);
    return JSValue.fromStringAtom(atom);
}

fn nativeCryptoGetRandomValues(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const target = args[0].toObject() orelse return args[0];

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    for (0..elements.items.len) |i| {
        var rand_byte: u8 = 0;
        _ = c.RAND_bytes(@ptrCast(&rand_byte), 1);
        var buf: [32]u8 = undefined;
        const key_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
        const key_atom = try vm.atom_table.intern(key_str);
        try target.setProperty(vm.allocator, key_atom, JSValue.fromInt32(rand_byte));
    }
    return args[0];
}

fn nativeBtoa(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const input_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };
    const enc = std.base64.standard.Encoder;
    const out_len = enc.calcSize(input_str.len);
    const out_buf = try vm.allocator.alloc(u8, out_len);
    defer vm.allocator.free(out_buf);
    _ = enc.encode(out_buf, input_str);
    const atom = try vm.atom_table.intern(out_buf);
    return JSValue.fromStringAtom(atom);
}

fn nativeAtob(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const input_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };
    const dec = std.base64.standard.Decoder;
    const out_len = dec.calcSizeForSlice(input_str) catch return error.InvalidCharacter;
    const out_buf = try vm.allocator.alloc(u8, out_len);
    defer vm.allocator.free(out_buf);
    try dec.decode(out_buf, input_str);
    const atom = try vm.atom_table.intern(out_buf);
    return JSValue.fromStringAtom(atom);
}

pub fn cloneValue(vm: *VM, val: JSValue) anyerror!JSValue {
    if (!val.isObject()) return val;
    const obj = val.toObject().?;
    if (obj.builtin_type == .Array) {
        var elements: std.ArrayList(JSValue) = .empty;
        defer elements.deinit(vm.allocator);
        try getArrayElements(vm, obj, &elements);
        var cloned_items: std.ArrayList(JSValue) = .empty;
        defer cloned_items.deinit(vm.allocator);
        for (elements.items) |item| {
            try cloned_items.append(vm.allocator, try cloneValue(vm, item));
        }
        const cloned_arr = try createArray(vm, cloned_items.items);
        return JSValue.fromObject(cloned_arr);
    }

    const cloned_obj = try vm.gc.allocateObject(obj.prototype);
    var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
    defer entries.deinit(vm.allocator);
    try obj.getPropertyEntries(vm.allocator, &entries);

    for (entries.items) |prop| {
        const cloned_prop = try cloneValue(vm, prop.value);
        try cloned_obj.setProperty(vm.allocator, prop.atom, cloned_prop);
    }
    return JSValue.fromObject(cloned_obj);
}

fn nativeStructuredClone(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    return try cloneValue(vm, args[0]);
}

fn nativeQueueMicrotask(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len > 0 and args[0].isObject()) {
        const obj = args[0].toObject().?;
        if (obj.native_fn) |fn_ptr| {
            _ = try fn_ptr(obj.native_ctx orelse undefined, JSValue.undefined_val, &[_]JSValue{});
        }
    }
    return JSValue.undefined_val;
}

fn nativeTextEncoderEncode(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));
    const str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => "",
    };
    var byte_values: std.ArrayList(JSValue) = .empty;
    defer byte_values.deinit(vm.allocator);
    for (str) |b| {
        try byte_values.append(vm.allocator, JSValue.fromInt32(b));
    }
    const arr = try createArray(vm, byte_values.items);
    return JSValue.fromObject(arr);
}

fn nativeTextEncoderConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const enc_fn = try vm.gc.allocateFunction(null, nativeTextEncoderEncode, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("encode"), JSValue.fromObject(enc_fn));
    return JSValue.fromObject(inst);
}

fn nativeTextDecoderDecode(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    const target = args[0].toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));

    var elements: std.ArrayList(JSValue) = .empty;
    defer elements.deinit(vm.allocator);
    try getArrayElements(vm, target, &elements);

    const buf = try vm.allocator.alloc(u8, elements.items.len);
    defer vm.allocator.free(buf);
    for (elements.items, 0..) |item, i| {
        buf[i] = @intCast(@max(0, @min(255, item.toInt32())));
    }
    const atom = try vm.atom_table.intern(buf);
    return JSValue.fromStringAtom(atom);
}

fn nativeTextDecoderConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const dec_fn = try vm.gc.allocateFunction(null, nativeTextDecoderDecode, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("decode"), JSValue.fromObject(dec_fn));
    return JSValue.fromObject(inst);
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

test "modern web and es2024 builtins: btoa atob crypto structuredClone object groupby textencoder" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    // 1. btoa and atob Base64 roundtrip
    const orig_str = "Davoth Browser Engine";
    const btoa_val = try nativeBtoa(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern(orig_str)),
    });
    try std.testing.expect(btoa_val.isString());
    const btoa_str = atom_table.get(btoa_val.toStringAtom());

    const atob_val = try nativeAtob(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{btoa_val});
    try std.testing.expect(atob_val.isString());
    const atob_str = atom_table.get(atob_val.toStringAtom());
    try std.testing.expectEqualStrings(orig_str, atob_str);
    _ = btoa_str;

    // 2. crypto.randomUUID
    const uuid_val = try nativeCryptoRandomUUID(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{});
    try std.testing.expect(uuid_val.isString());
    const uuid_str = atom_table.get(uuid_val.toStringAtom());
    try std.testing.expectEqual(@as(usize, 36), uuid_str.len);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[8]);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[13]);
    try std.testing.expectEqual(@as(u8, '4'), uuid_str[14]); // RFC 4122 v4
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[18]);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[23]);

    // 3. Promise.withResolvers
    const resolvers_val = try nativePromiseWithResolvers(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{});
    try std.testing.expect(resolvers_val.isObject());
    const res_obj = resolvers_val.toObject().?;
    try std.testing.expect(res_obj.getProperty(try atom_table.intern("promise")) != null);
    try std.testing.expect(res_obj.getProperty(try atom_table.intern("resolve")) != null);
    try std.testing.expect(res_obj.getProperty(try atom_table.intern("reject")) != null);

    // 4. Object.keys, values, and assign
    const test_obj = try vm.gc.allocateObject(null);
    try test_obj.setProperty(allocator, try atom_table.intern("a"), JSValue.fromInt32(1));
    try test_obj.setProperty(allocator, try atom_table.intern("b"), JSValue.fromInt32(2));

    const keys_val = try nativeObjectKeys(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{JSValue.fromObject(test_obj)});
    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(allocator);
    try getArrayElements(vm, keys_val.toObject().?, &keys_list);
    try std.testing.expectEqual(@as(usize, 2), keys_list.items.len);

    const values_val = try nativeObjectValues(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{JSValue.fromObject(test_obj)});
    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(allocator);
    try getArrayElements(vm, values_val.toObject().?, &vals_list);
    try std.testing.expectEqual(@as(usize, 2), vals_list.items.len);

    // 5. structuredClone
    const cloned_val = try nativeStructuredClone(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{JSValue.fromObject(test_obj)});
    try std.testing.expect(cloned_val.isObject());
    const cloned_obj = cloned_val.toObject().?;
    try std.testing.expect(cloned_obj != test_obj);
    const prop_a = cloned_obj.getProperty(try atom_table.intern("a")).?;
    try std.testing.expectEqual(@as(i32, 1), prop_a.toInt32());

    // 6. TextEncoder and TextDecoder roundtrip
    const enc_val = try nativeTextEncoderEncode(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("WebStandards")),
    });
    try std.testing.expect(enc_val.isObject());

    const dec_val = try nativeTextDecoderDecode(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{enc_val});
    try std.testing.expect(dec_val.isString());
    try std.testing.expectEqualStrings("WebStandards", atom_table.get(dec_val.toStringAtom()));

    // 7. Object.groupBy (ES2024)
    const items_for_group = [_]JSValue{
        JSValue.fromInt32(1),
        JSValue.fromInt32(2),
        JSValue.fromInt32(3),
        JSValue.fromInt32(4),
    };
    const arr_to_group = try createArray(vm, &items_for_group);

    const even_atom = try atom_table.intern("even");
    const odd_atom = try atom_table.intern("odd");

    const GroupCallback = struct {
        fn cb(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
            const table: *AtomTable = @ptrCast(@alignCast(ctx));
            const num = args[0].toInt32();
            if (@mod(num, 2) == 0) {
                return JSValue.fromStringAtom(try table.intern("even"));
            } else {
                return JSValue.fromStringAtom(try table.intern("odd"));
            }
        }
    };

    const cb_fn_obj = try vm.gc.allocateFunction(null, GroupCallback.cb, @ptrCast(atom_table));
    const grouped_val = try nativeObjectGroupBy(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromObject(arr_to_group),
        JSValue.fromObject(cb_fn_obj),
    });
    try std.testing.expect(grouped_val.isObject());
    const g_obj = grouped_val.toObject().?;
    try std.testing.expect(g_obj.getProperty(even_atom) != null);
    try std.testing.expect(g_obj.getProperty(odd_atom) != null);
}
