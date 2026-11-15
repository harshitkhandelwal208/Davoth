//! Standard ECMAScript built-in global objects and functions.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const VM = @import("interpreter.zig").VM;
const c = @import("../common/c.zig");
const url_mod = @import("../common/url.zig");
const URL = url_mod.URL;
const URLSearchParams = url_mod.URLSearchParams;
const time = @import("../common/time.zig");
const WasmDecoder = @import("../wasm/decoder.zig").Decoder;
const WasmValidator = @import("../wasm/validator.zig").Validator;
const WasmInstance = @import("../wasm/runtime.zig").Instance;
const Node = @import("../dom/node.zig").Node;
const TreeBuilder = @import("../html/tree_builder.zig").TreeBuilder;

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

    const self_atom = try table.intern("self");
    try global.setProperty(alloc, self_atom, JSValue.fromObject(global));

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

    // Web Storage: Storage, localStorage & sessionStorage
    const storage_ctor = try vm.gc.allocateFunction(null, nativeStorageConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Storage"), JSValue.fromObject(storage_ctor));

    const local_storage_obj = try createStorage(vm);
    try global.setProperty(alloc, try table.intern("localStorage"), JSValue.fromObject(local_storage_obj));

    const session_storage_obj = try createStorage(vm);
    try global.setProperty(alloc, try table.intern("sessionStorage"), JSValue.fromObject(session_storage_obj));

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

    // crypto: randomUUID, getRandomValues, subtle.digest
    const crypto_obj = try vm.gc.allocateObject(null);
    const uuid_fn = try vm.gc.allocateFunction(null, nativeCryptoRandomUUID, @ptrCast(vm));
    try crypto_obj.setProperty(alloc, try table.intern("randomUUID"), JSValue.fromObject(uuid_fn));

    const rand_values_fn = try vm.gc.allocateFunction(null, nativeCryptoGetRandomValues, @ptrCast(vm));
    try crypto_obj.setProperty(alloc, try table.intern("getRandomValues"), JSValue.fromObject(rand_values_fn));

    const subtle_obj = try vm.gc.allocateObject(null);
    const digest_fn = try vm.gc.allocateFunction(null, nativeSubtleDigest, @ptrCast(vm));
    try subtle_obj.setProperty(alloc, try table.intern("digest"), JSValue.fromObject(digest_fn));
    try crypto_obj.setProperty(alloc, try table.intern("subtle"), JSValue.fromObject(subtle_obj));

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

    // URL & URLSearchParams Web APIs
    const url_params_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("URLSearchParams"), JSValue.fromObject(url_params_fn));

    const url_fn = try vm.gc.allocateFunction(null, nativeUrlConstructor, @ptrCast(vm));
    const create_obj_url_fn = try vm.gc.allocateFunction(null, nativeUrlCreateObjectURL, @ptrCast(vm));
    try url_fn.setProperty(alloc, try table.intern("createObjectURL"), JSValue.fromObject(create_obj_url_fn));
    const revoke_obj_url_fn = try vm.gc.allocateFunction(null, nativeUrlRevokeObjectURL, @ptrCast(vm));
    try url_fn.setProperty(alloc, try table.intern("revokeObjectURL"), JSValue.fromObject(revoke_obj_url_fn));
    try global.setProperty(alloc, try table.intern("URL"), JSValue.fromObject(url_fn));

    // Blob Web API
    const blob_ctor = try vm.gc.allocateFunction(null, nativeBlobConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Blob"), JSValue.fromObject(blob_ctor));

    // AbortController & AbortSignal Web APIs
    const abort_ctrl_fn = try vm.gc.allocateFunction(null, nativeAbortControllerConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("AbortController"), JSValue.fromObject(abort_ctrl_fn));

    const abort_sig_fn = try vm.gc.allocateFunction(null, nativeAbortSignalConstructor, @ptrCast(vm));
    const sig_abort_static = try vm.gc.allocateFunction(null, nativeAbortSignalStaticAbort, @ptrCast(vm));
    try abort_sig_fn.setProperty(alloc, try table.intern("abort"), JSValue.fromObject(sig_abort_static));
    const sig_timeout_static = try vm.gc.allocateFunction(null, nativeAbortSignalStaticTimeout, @ptrCast(vm));
    try abort_sig_fn.setProperty(alloc, try table.intern("timeout"), JSValue.fromObject(sig_timeout_static));
    try global.setProperty(alloc, try table.intern("AbortSignal"), JSValue.fromObject(abort_sig_fn));

    // FormData Web API
    const form_data_fn = try vm.gc.allocateFunction(null, nativeFormDataConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("FormData"), JSValue.fromObject(form_data_fn));

    // WebSocket Web API
    const ws_fn = try vm.gc.allocateFunction(null, nativeWebSocketConstructor, @ptrCast(vm));
    try ws_fn.setProperty(alloc, try table.intern("CONNECTING"), JSValue.fromInt32(0));
    try ws_fn.setProperty(alloc, try table.intern("OPEN"), JSValue.fromInt32(1));
    try ws_fn.setProperty(alloc, try table.intern("CLOSING"), JSValue.fromInt32(2));
    try ws_fn.setProperty(alloc, try table.intern("CLOSED"), JSValue.fromInt32(3));
    try global.setProperty(alloc, try table.intern("WebSocket"), JSValue.fromObject(ws_fn));

    // navigator Web API
    const nav_obj = try vm.gc.allocateObject(null);
    try nav_obj.setProperty(alloc, try table.intern("userAgent"), JSValue.fromStringAtom(try table.intern("Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Davoth/1.0")));
    try nav_obj.setProperty(alloc, try table.intern("platform"), JSValue.fromStringAtom(try table.intern("Linux x86_64")));
    try nav_obj.setProperty(alloc, try table.intern("language"), JSValue.fromStringAtom(try table.intern("en-US")));
    const lang_en_us = JSValue.fromStringAtom(try table.intern("en-US"));
    const lang_en = JSValue.fromStringAtom(try table.intern("en"));
    const lang_arr = try createArray(vm, &[_]JSValue{ lang_en_us, lang_en });
    try nav_obj.setProperty(alloc, try table.intern("languages"), JSValue.fromObject(lang_arr));
    try nav_obj.setProperty(alloc, try table.intern("onLine"), JSValue.true_val);
    try nav_obj.setProperty(alloc, try table.intern("cookieEnabled"), JSValue.true_val);
    try nav_obj.setProperty(alloc, try table.intern("hardwareConcurrency"), JSValue.fromInt32(8));
    try global.setProperty(alloc, try table.intern("navigator"), JSValue.fromObject(nav_obj));

    // location Web API (window.location)
    const loc_obj = try vm.gc.allocateObject(null);
    try loc_obj.setProperty(alloc, try table.intern("href"), JSValue.fromStringAtom(try table.intern("https://davoth.org/")));
    try loc_obj.setProperty(alloc, try table.intern("origin"), JSValue.fromStringAtom(try table.intern("https://davoth.org")));
    try loc_obj.setProperty(alloc, try table.intern("protocol"), JSValue.fromStringAtom(try table.intern("https:")));
    try loc_obj.setProperty(alloc, try table.intern("host"), JSValue.fromStringAtom(try table.intern("davoth.org")));
    try loc_obj.setProperty(alloc, try table.intern("hostname"), JSValue.fromStringAtom(try table.intern("davoth.org")));
    try loc_obj.setProperty(alloc, try table.intern("port"), JSValue.fromStringAtom(try table.intern("")));
    try loc_obj.setProperty(alloc, try table.intern("pathname"), JSValue.fromStringAtom(try table.intern("/")));
    try loc_obj.setProperty(alloc, try table.intern("search"), JSValue.fromStringAtom(try table.intern("")));
    try loc_obj.setProperty(alloc, try table.intern("hash"), JSValue.fromStringAtom(try table.intern("")));
    const loc_assign_fn = try vm.gc.allocateFunction(null, nativeLocationAssign, @ptrCast(vm));
    try loc_obj.setProperty(alloc, try table.intern("assign"), JSValue.fromObject(loc_assign_fn));
    try loc_obj.setProperty(alloc, try table.intern("replace"), JSValue.fromObject(loc_assign_fn));
    const loc_reload_fn = try vm.gc.allocateFunction(null, nativeLocationReload, @ptrCast(vm));
    try loc_obj.setProperty(alloc, try table.intern("reload"), JSValue.fromObject(loc_reload_fn));
    try loc_obj.setProperty(alloc, try table.intern("toString"), JSValue.fromObject(loc_assign_fn));
    try global.setProperty(alloc, try table.intern("location"), JSValue.fromObject(loc_obj));

    // history Web API (window.history)
    const hist_obj = try vm.gc.allocateObject(null);
    try hist_obj.setProperty(alloc, try table.intern("length"), JSValue.fromInt32(1));
    try hist_obj.setProperty(alloc, try table.intern("state"), JSValue.null_val);
    const push_state_fn = try vm.gc.allocateFunction(null, nativeHistoryPushState, @ptrCast(vm));
    try hist_obj.setProperty(alloc, try table.intern("pushState"), JSValue.fromObject(push_state_fn));
    const rep_state_fn = try vm.gc.allocateFunction(null, nativeHistoryReplaceState, @ptrCast(vm));
    try hist_obj.setProperty(alloc, try table.intern("replaceState"), JSValue.fromObject(rep_state_fn));
    const hist_back_fn = try vm.gc.allocateFunction(null, nativeHistoryBack, @ptrCast(vm));
    try hist_obj.setProperty(alloc, try table.intern("back"), JSValue.fromObject(hist_back_fn));
    const hist_fwd_fn = try vm.gc.allocateFunction(null, nativeHistoryForward, @ptrCast(vm));
    try hist_obj.setProperty(alloc, try table.intern("forward"), JSValue.fromObject(hist_fwd_fn));
    const hist_go_fn = try vm.gc.allocateFunction(null, nativeHistoryGo, @ptrCast(vm));
    try hist_obj.setProperty(alloc, try table.intern("go"), JSValue.fromObject(hist_go_fn));
    try global.setProperty(alloc, try table.intern("history"), JSValue.fromObject(hist_obj));

    // performance Web API
    const perf_obj = try vm.gc.allocateObject(null);
    const perf_now_fn = try vm.gc.allocateFunction(null, nativePerformanceNow, @ptrCast(vm));
    try perf_obj.setProperty(alloc, try table.intern("now"), JSValue.fromObject(perf_now_fn));
    try global.setProperty(alloc, try table.intern("performance"), JSValue.fromObject(perf_obj));

    // requestAnimationFrame & cancelAnimationFrame
    const raf_fn = try vm.gc.allocateFunction(null, nativeRequestAnimationFrame, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("requestAnimationFrame"), JSValue.fromObject(raf_fn));
    const caf_fn = try vm.gc.allocateFunction(null, nativeCancelAnimationFrame, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("cancelAnimationFrame"), JSValue.fromObject(caf_fn));

    // EventTarget methods on window / global
    const win_add_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetAddEventListener, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("addEventListener"), JSValue.fromObject(win_add_ev_fn));
    const win_rem_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetRemoveEventListener, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("removeEventListener"), JSValue.fromObject(win_rem_ev_fn));
    const win_disp_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetDispatchEvent, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("dispatchEvent"), JSValue.fromObject(win_disp_ev_fn));

    // Event, CustomEvent, MouseEvent, KeyboardEvent, FocusEvent constructors
    const ev_ctor = try vm.gc.allocateFunction(null, nativeEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Event"), JSValue.fromObject(ev_ctor));
    const cust_ev_ctor = try vm.gc.allocateFunction(null, nativeCustomEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("CustomEvent"), JSValue.fromObject(cust_ev_ctor));
    const mouse_ev_ctor = try vm.gc.allocateFunction(null, nativeMouseEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("MouseEvent"), JSValue.fromObject(mouse_ev_ctor));
    const kb_ev_ctor = try vm.gc.allocateFunction(null, nativeKeyboardEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("KeyboardEvent"), JSValue.fromObject(kb_ev_ctor));
    const focus_ev_ctor = try vm.gc.allocateFunction(null, nativeFocusEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("FocusEvent"), JSValue.fromObject(focus_ev_ctor));
    const popstate_ctor = try vm.gc.allocateFunction(null, nativePopStateEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("PopStateEvent"), JSValue.fromObject(popstate_ctor));
    const hashchange_ctor = try vm.gc.allocateFunction(null, nativeHashChangeEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("HashChangeEvent"), JSValue.fromObject(hashchange_ctor));
    const pointer_ev_ctor = try vm.gc.allocateFunction(null, nativePointerEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("PointerEvent"), JSValue.fromObject(pointer_ev_ctor));
    const input_ev_ctor = try vm.gc.allocateFunction(null, nativeInputEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("InputEvent"), JSValue.fromObject(input_ev_ctor));
    const submit_ev_ctor = try vm.gc.allocateFunction(null, nativeSubmitEventConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("SubmitEvent"), JSValue.fromObject(submit_ev_ctor));
    try global.setProperty(alloc, try table.intern("UIEvent"), JSValue.fromObject(ev_ctor));

    // Headers, Request, Response constructors
    const headers_ctor = try vm.gc.allocateFunction(null, nativeHeadersConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Headers"), JSValue.fromObject(headers_ctor));
    const req_ctor = try vm.gc.allocateFunction(null, nativeRequestConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Request"), JSValue.fromObject(req_ctor));
    const resp_ctor = try vm.gc.allocateFunction(null, nativeResponseConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Response"), JSValue.fromObject(resp_ctor));

    // WebAssembly object
    const wasm_obj = try vm.gc.allocateObject(null);
    const wasm_val_fn = try vm.gc.allocateFunction(null, nativeWasmValidate, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("validate"), JSValue.fromObject(wasm_val_fn));
    const wasm_comp_fn = try vm.gc.allocateFunction(null, nativeWasmCompile, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("compile"), JSValue.fromObject(wasm_comp_fn));
    const wasm_inst_fn = try vm.gc.allocateFunction(null, nativeWasmInstantiate, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("instantiate"), JSValue.fromObject(wasm_inst_fn));
    const wasm_mem_fn = try vm.gc.allocateFunction(null, nativeWasmMemoryConstructor, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("Memory"), JSValue.fromObject(wasm_mem_fn));
    const wasm_mod_fn = try vm.gc.allocateFunction(null, nativeWasmModuleConstructor, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("Module"), JSValue.fromObject(wasm_mod_fn));
    const wasm_ins_fn = try vm.gc.allocateFunction(null, nativeWasmInstanceConstructor, @ptrCast(vm));
    try wasm_obj.setProperty(alloc, try table.intern("Instance"), JSValue.fromObject(wasm_ins_fn));
    try global.setProperty(alloc, try table.intern("WebAssembly"), JSValue.fromObject(wasm_obj));

    // document Web API
    const doc_obj = try createJsDocument(vm);
    try doc_obj.setProperty(alloc, try table.intern("location"), JSValue.fromObject(loc_obj));
    try global.setProperty(alloc, try table.intern("document"), JSValue.fromObject(doc_obj));

    // Window viewport dimensions & properties
    try global.setProperty(alloc, try table.intern("innerWidth"), JSValue.fromInt32(1280));
    try global.setProperty(alloc, try table.intern("innerHeight"), JSValue.fromInt32(720));
    try global.setProperty(alloc, try table.intern("outerWidth"), JSValue.fromInt32(1280));
    try global.setProperty(alloc, try table.intern("outerHeight"), JSValue.fromInt32(720));
    try global.setProperty(alloc, try table.intern("scrollX"), JSValue.fromInt32(0));
    try global.setProperty(alloc, try table.intern("scrollY"), JSValue.fromInt32(0));
    try global.setProperty(alloc, try table.intern("pageXOffset"), JSValue.fromInt32(0));
    try global.setProperty(alloc, try table.intern("pageYOffset"), JSValue.fromInt32(0));
    try global.setProperty(alloc, try table.intern("devicePixelRatio"), JSValue.fromFloat64(1.0));

    // Window scroll methods
    const scroll_fn = try vm.gc.allocateFunction(null, nativeWindowScrollTo, null);
    try global.setProperty(alloc, try table.intern("scrollTo"), JSValue.fromObject(scroll_fn));
    try global.setProperty(alloc, try table.intern("scroll"), JSValue.fromObject(scroll_fn));
    try global.setProperty(alloc, try table.intern("scrollBy"), JSValue.fromObject(scroll_fn));

    // Window dialogs
    const alert_fn = try vm.gc.allocateFunction(null, nativeWindowAlert, null);
    try global.setProperty(alloc, try table.intern("alert"), JSValue.fromObject(alert_fn));
    const confirm_fn = try vm.gc.allocateFunction(null, nativeWindowConfirm, null);
    try global.setProperty(alloc, try table.intern("confirm"), JSValue.fromObject(confirm_fn));
    const prompt_fn = try vm.gc.allocateFunction(null, nativeWindowPrompt, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("prompt"), JSValue.fromObject(prompt_fn));

    // Screen object
    const screen_obj = try vm.gc.allocateObject(null);
    try screen_obj.setProperty(alloc, try table.intern("width"), JSValue.fromInt32(1920));
    try screen_obj.setProperty(alloc, try table.intern("height"), JSValue.fromInt32(1080));
    try screen_obj.setProperty(alloc, try table.intern("availWidth"), JSValue.fromInt32(1920));
    try screen_obj.setProperty(alloc, try table.intern("availHeight"), JSValue.fromInt32(1040));
    try screen_obj.setProperty(alloc, try table.intern("colorDepth"), JSValue.fromInt32(24));
    try screen_obj.setProperty(alloc, try table.intern("pixelDepth"), JSValue.fromInt32(24));
    try global.setProperty(alloc, try table.intern("screen"), JSValue.fromObject(screen_obj));

    // getComputedStyle & matchMedia
    const get_cs_fn = try vm.gc.allocateFunction(null, nativeGetComputedStyle, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("getComputedStyle"), JSValue.fromObject(get_cs_fn));
    const match_media_fn = try vm.gc.allocateFunction(null, nativeMatchMedia, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("matchMedia"), JSValue.fromObject(match_media_fn));

    // Node interface constants
    const node_ctor = try vm.gc.allocateObject(null);
    try node_ctor.setProperty(alloc, try table.intern("ELEMENT_NODE"), JSValue.fromInt32(1));
    try node_ctor.setProperty(alloc, try table.intern("ATTRIBUTE_NODE"), JSValue.fromInt32(2));
    try node_ctor.setProperty(alloc, try table.intern("TEXT_NODE"), JSValue.fromInt32(3));
    try node_ctor.setProperty(alloc, try table.intern("CDATA_SECTION_NODE"), JSValue.fromInt32(4));
    try node_ctor.setProperty(alloc, try table.intern("COMMENT_NODE"), JSValue.fromInt32(8));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_NODE"), JSValue.fromInt32(9));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_FRAGMENT_NODE"), JSValue.fromInt32(11));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_DISCONNECTED"), JSValue.fromInt32(1));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_PRECEDING"), JSValue.fromInt32(2));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_FOLLOWING"), JSValue.fromInt32(4));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_CONTAINS"), JSValue.fromInt32(8));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_CONTAINED_BY"), JSValue.fromInt32(16));
    try node_ctor.setProperty(alloc, try table.intern("DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC"), JSValue.fromInt32(32));
    try global.setProperty(alloc, try table.intern("Node"), JSValue.fromObject(node_ctor));

    // Modern Observers: MutationObserver, ResizeObserver, IntersectionObserver
    const mut_obs_ctor = try vm.gc.allocateFunction(null, nativeMutationObserverConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("MutationObserver"), JSValue.fromObject(mut_obs_ctor));
    const rsz_obs_ctor = try vm.gc.allocateFunction(null, nativeResizeObserverConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("ResizeObserver"), JSValue.fromObject(rsz_obs_ctor));
    const int_obs_ctor = try vm.gc.allocateFunction(null, nativeIntersectionObserverConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("IntersectionObserver"), JSValue.fromObject(int_obs_ctor));

    // Intl global object
    const intl_obj = try vm.gc.allocateObject(null);
    const dtf_ctor = try vm.gc.allocateFunction(null, nativeDateTimeFormatConstructor, @ptrCast(vm));
    try intl_obj.setProperty(alloc, try table.intern("DateTimeFormat"), JSValue.fromObject(dtf_ctor));
    const nf_ctor = try vm.gc.allocateFunction(null, nativeNumberFormatConstructor, @ptrCast(vm));
    try intl_obj.setProperty(alloc, try table.intern("NumberFormat"), JSValue.fromObject(nf_ctor));
    try global.setProperty(alloc, try table.intern("Intl"), JSValue.fromObject(intl_obj));

    // DOMParser constructor
    const dom_parser_ctor = try vm.gc.allocateFunction(null, nativeDOMParserConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("DOMParser"), JSValue.fromObject(dom_parser_ctor));

    // XMLSerializer constructor
    const xml_serializer_ctor = try vm.gc.allocateFunction(null, nativeXMLSerializerConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("XMLSerializer"), JSValue.fromObject(xml_serializer_ctor));

    // BroadcastChannel constructor
    const bc_ctor = try vm.gc.allocateFunction(null, nativeBroadcastChannelConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("BroadcastChannel"), JSValue.fromObject(bc_ctor));

    // customElements registry
    const custom_elements_obj = try vm.gc.allocateObject(null);
    const registry_obj = try vm.gc.allocateObject(null);
    try custom_elements_obj.setProperty(alloc, try table.intern("_registry"), JSValue.fromObject(registry_obj));

    const ce_def_fn = try vm.gc.allocateFunction(null, nativeCustomElementsDefine, @ptrCast(vm));
    try custom_elements_obj.setProperty(alloc, try table.intern("define"), JSValue.fromObject(ce_def_fn));

    const ce_get_fn = try vm.gc.allocateFunction(null, nativeCustomElementsGet, @ptrCast(vm));
    try custom_elements_obj.setProperty(alloc, try table.intern("get"), JSValue.fromObject(ce_get_fn));

    const ce_when_def_fn = try vm.gc.allocateFunction(null, nativeCustomElementsWhenDefined, @ptrCast(vm));
    try custom_elements_obj.setProperty(alloc, try table.intern("whenDefined"), JSValue.fromObject(ce_when_def_fn));

    try global.setProperty(alloc, try table.intern("customElements"), JSValue.fromObject(custom_elements_obj));

    // Range constructor
    const range_ctor = try vm.gc.allocateFunction(null, nativeRangeConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Range"), JSValue.fromObject(range_ctor));

    // Selection constructor & getSelection
    const get_sel_fn = try vm.gc.allocateFunction(null, nativeGetSelection, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("getSelection"), JSValue.fromObject(get_sel_fn));
    const sel_ctor = try vm.gc.allocateFunction(null, nativeSelectionConstructor, @ptrCast(vm));
    try global.setProperty(alloc, try table.intern("Selection"), JSValue.fromObject(sel_ctor));
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

pub fn createStorage(vm: *VM) anyerror!*JSObject {
    const alloc = vm.allocator;
    const table = vm.atom_table;
    const obj = try vm.gc.allocateObject(null);

    const keys_arr = try createArray(vm, &[_]JSValue{});
    try obj.setProperty(alloc, try table.intern("_keys"), JSValue.fromObject(keys_arr));
    try obj.setProperty(alloc, try table.intern("length"), JSValue.fromInt32(0));

    const set_fn = try vm.gc.allocateFunction(null, nativeStorageSetItem, @ptrCast(vm));
    try obj.setProperty(alloc, try table.intern("setItem"), JSValue.fromObject(set_fn));

    const get_fn = try vm.gc.allocateFunction(null, nativeStorageGetItem, @ptrCast(vm));
    try obj.setProperty(alloc, try table.intern("getItem"), JSValue.fromObject(get_fn));

    const rem_fn = try vm.gc.allocateFunction(null, nativeStorageRemoveItem, @ptrCast(vm));
    try obj.setProperty(alloc, try table.intern("removeItem"), JSValue.fromObject(rem_fn));

    const clear_fn = try vm.gc.allocateFunction(null, nativeStorageClear, @ptrCast(vm));
    try obj.setProperty(alloc, try table.intern("clear"), JSValue.fromObject(clear_fn));

    const key_fn = try vm.gc.allocateFunction(null, nativeStorageKey, @ptrCast(vm));
    try obj.setProperty(alloc, try table.intern("key"), JSValue.fromObject(key_fn));

    return obj;
}

fn nativeStorageConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const s = try createStorage(vm);
    return JSValue.fromObject(s);
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

    var val_buf: [256]u8 = undefined;
    const val_str = switch (args[1].getType()) {
        .String => vm.atom_table.get(args[1].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&val_buf, "{d}", .{args[1].toInt32()}) catch "0",
        .Float64 => std.fmt.bufPrint(&val_buf, "{d}", .{args[1].toFloat64()}) catch "0",
        .Boolean => if (args[1].toBoolean()) "true" else "false",
        .Null => "null",
        .Undefined => "undefined",
        else => "[object Object]",
    };
    const val_atom = try vm.atom_table.intern(val_str);
    try target.setProperty(vm.allocator, key_atom, JSValue.fromStringAtom(val_atom));

    const keys_atom = try vm.atom_table.intern("_keys");
    if (target.getProperty(keys_atom)) |kv| {
        if (kv.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            var exists = false;
            for (list.items) |it| {
                if (it.isString() and std.mem.eql(u8, vm.atom_table.get(it.toStringAtom()), key_str)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                try list.append(vm.allocator, JSValue.fromStringAtom(key_atom));
                const new_arr = try createArray(vm, list.items);
                try target.setProperty(vm.allocator, keys_atom, JSValue.fromObject(new_arr));
                try target.setProperty(vm.allocator, try vm.atom_table.intern("length"), JSValue.fromInt32(@intCast(list.items.len)));
            }
        }
    }
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
    const v = target.getProperty(key_atom) orelse return JSValue.null_val;
    if (v.isNull()) return JSValue.null_val;
    return v;
}

fn nativeStorageRemoveItem(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    var key_buf: [128]u8 = undefined;
    const key_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&key_buf, "{d}", .{args[0].toInt32()}) catch "0",
        else => "key",
    };
    const key_atom = vm.atom_table.map.get(key_str) orelse return JSValue.undefined_val;
    try target.setProperty(vm.allocator, key_atom, JSValue.null_val);

    const keys_atom = try vm.atom_table.intern("_keys");
    if (target.getProperty(keys_atom)) |kv| {
        if (kv.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            var rem_idx: ?usize = null;
            for (list.items, 0..) |it, idx| {
                if (it.isString() and std.mem.eql(u8, vm.atom_table.get(it.toStringAtom()), key_str)) {
                    rem_idx = idx;
                    break;
                }
            }
            if (rem_idx) |idx| {
                _ = list.orderedRemove(idx);
                const new_arr = try createArray(vm, list.items);
                try target.setProperty(vm.allocator, keys_atom, JSValue.fromObject(new_arr));
                try target.setProperty(vm.allocator, try vm.atom_table.intern("length"), JSValue.fromInt32(@intCast(list.items.len)));
            }
        }
    }
    return JSValue.undefined_val;
}

fn nativeStorageClear(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const target = this_val.toObject() orelse return JSValue.undefined_val;

    const keys_atom = try vm.atom_table.intern("_keys");
    if (target.getProperty(keys_atom)) |kv| {
        if (kv.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            for (list.items) |it| {
                if (it.isString()) {
                    try target.setProperty(vm.allocator, it.toStringAtom(), JSValue.null_val);
                }
            }
            const empty_arr = try createArray(vm, &[_]JSValue{});
            try target.setProperty(vm.allocator, keys_atom, JSValue.fromObject(empty_arr));
            try target.setProperty(vm.allocator, try vm.atom_table.intern("length"), JSValue.fromInt32(0));
        }
    }
    return JSValue.undefined_val;
}

fn nativeStorageKey(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isNumber()) return JSValue.null_val;
    const idx = args[0].toInt32();
    if (idx < 0) return JSValue.null_val;
    const target = this_val.toObject() orelse return JSValue.null_val;

    const keys_atom = try vm.atom_table.intern("_keys");
    if (target.getProperty(keys_atom)) |kv| {
        if (kv.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            if (@as(usize, @intCast(idx)) < list.items.len) {
                return list.items[@as(usize, @intCast(idx))];
            }
        }
    }
    return JSValue.null_val;
}

fn nativeFetch(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const body_str = if (args.len > 1 and args[1].isObject())
        (args[1].toObject().?.getProperty(try vm.atom_table.intern("body")) orelse JSValue.fromStringAtom(try vm.atom_table.intern("{}")))
    else
        JSValue.fromStringAtom(try vm.atom_table.intern("{}"));

    return try nativeResponseConstructor(ctx, JSValue.undefined_val, &[_]JSValue{body_str});
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

fn createPromiseObject(vm: *VM, val: JSValue) anyerror!*JSObject {
    const p_obj = try vm.gc.allocateObject(null);
    p_obj.builtin_type = .Promise;
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("_value"), val);
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("_state"), JSValue.fromStringAtom(try vm.atom_table.intern("fulfilled")));
    const then_fn = try vm.gc.allocateFunction(null, nativePromiseThen, @ptrCast(vm));
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("then"), JSValue.fromObject(then_fn));
    const catch_fn = try vm.gc.allocateFunction(null, nativePromiseCatch, @ptrCast(vm));
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("catch"), JSValue.fromObject(catch_fn));
    return p_obj;
}

fn nativePromiseThen(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const val = inst.getProperty(try vm.atom_table.intern("_value")) orelse JSValue.undefined_val;
    if (args.len > 0 and args[0].isObject()) {
        const next_val = try vm.call(args[0], JSValue.undefined_val, &[_]JSValue{val});
        const next_prom = try createPromiseObject(vm, next_val);
        return JSValue.fromObject(next_prom);
    }
    return this_val;
}

fn nativePromiseCatch(_: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    return this_val;
}

fn nativePromiseResolve(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len > 0 and args[0].isObject() and args[0].toObject().?.builtin_type == .Promise) {
        return args[0];
    }
    const val = if (args.len > 0) args[0] else JSValue.undefined_val;
    const p_obj = try createPromiseObject(vm, val);
    return JSValue.fromObject(p_obj);
}

fn nativePromiseReject(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const val = if (args.len > 0) args[0] else JSValue.undefined_val;
    const p_obj = try vm.gc.allocateObject(null);
    p_obj.builtin_type = .Promise;
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("_value"), val);
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("_state"), JSValue.fromStringAtom(try vm.atom_table.intern("rejected")));
    const then_fn = try vm.gc.allocateFunction(null, nativePromiseThen, @ptrCast(vm));
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("then"), JSValue.fromObject(then_fn));
    const catch_fn = try vm.gc.allocateFunction(null, nativePromiseCatch, @ptrCast(vm));
    try p_obj.setProperty(vm.allocator, try vm.atom_table.intern("catch"), JSValue.fromObject(catch_fn));
    return JSValue.fromObject(p_obj);
}

fn jsonValueToJsValue(vm: *VM, val: std.json.Value) anyerror!JSValue {
    switch (val) {
        .null => return JSValue.null_val,
        .bool => |b| return if (b) JSValue.true_val else JSValue.false_val,
        .integer => |i| {
            if (i >= std.math.minInt(i32) and i <= std.math.maxInt(i32)) {
                return JSValue.fromInt32(@intCast(i));
            } else {
                return JSValue.fromFloat64(@floatFromInt(i));
            }
        },
        .float => |f| return JSValue.fromFloat64(f),
        .number_string => |s| {
            if (std.fmt.parseInt(i32, s, 10)) |i| {
                return JSValue.fromInt32(i);
            } else |_| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    return JSValue.fromFloat64(f);
                } else |_| {
                    return JSValue.fromFloat64(0);
                }
            }
        },
        .string => |s| {
            const atom = try vm.atom_table.intern(s);
            return JSValue.fromStringAtom(atom);
        },
        .array => |arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            for (arr.items) |item| {
                const js_item = try jsonValueToJsValue(vm, item);
                try items.append(vm.allocator, js_item);
            }
            const js_arr = try createArray(vm, items.items);
            return JSValue.fromObject(js_arr);
        },
        .object => |obj| {
            const js_obj = try vm.gc.allocateObject(null);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const atom = try vm.atom_table.intern(entry.key_ptr.*);
                const js_val = try jsonValueToJsValue(vm, entry.value_ptr.*);
                try js_obj.setProperty(vm.allocator, atom, js_val);
            }
            return JSValue.fromObject(js_obj);
        },
    }
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

    var parsed = std.json.parseFromSlice(std.json.Value, vm.allocator, json_str, .{}) catch {
        return JSValue.null_val;
    };
    defer parsed.deinit();

    var res = try jsonValueToJsValue(vm, parsed.value);
    if (args.len > 1 and args[1].isObject()) {
        const root_holder = try vm.gc.allocateObject(null);
        try root_holder.setProperty(vm.allocator, try vm.atom_table.intern(""), res);
        const empty_atom = try vm.atom_table.intern("");
        res = try vm.call(args[1], JSValue.fromObject(root_holder), &[_]JSValue{
            JSValue.fromStringAtom(empty_atom),
            res,
        });
    }
    return res;
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

// WHATWG URLSearchParams implementation
fn nativeUrlSearchParamsConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);

    var query_str: []const u8 = "";
    if (args.len > 0 and args[0].isString()) {
        query_str = vm.atom_table.get(args[0].toStringAtom());
    }

    var params = try URLSearchParams.init(vm.allocator, query_str);
    defer params.deinit();

    var k_values: std.ArrayList(JSValue) = .empty;
    defer k_values.deinit(vm.allocator);
    var v_values: std.ArrayList(JSValue) = .empty;
    defer v_values.deinit(vm.allocator);

    for (params.params.items) |p| {
        const k_atom = try vm.atom_table.intern(p.key);
        const v_atom = try vm.atom_table.intern(p.value);
        try k_values.append(vm.allocator, JSValue.fromStringAtom(k_atom));
        try v_values.append(vm.allocator, JSValue.fromStringAtom(v_atom));
    }

    const keys_arr = try createArray(vm, k_values.items);
    const vals_arr = try createArray(vm, v_values.items);

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_keys"), JSValue.fromObject(keys_arr));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_values"), JSValue.fromObject(vals_arr));

    const get_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsGet, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("get"), JSValue.fromObject(get_fn));

    const get_all_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsGetAll, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getAll"), JSValue.fromObject(get_all_fn));

    const has_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsHas, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("has"), JSValue.fromObject(has_fn));

    const set_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsSet, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("set"), JSValue.fromObject(set_fn));

    const append_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsAppend, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("append"), JSValue.fromObject(append_fn));

    const delete_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsDelete, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("delete"), JSValue.fromObject(delete_fn));

    const to_string_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsToString, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("toString"), JSValue.fromObject(to_string_fn));

    return JSValue.fromObject(inst);
}

fn nativeUrlSearchParamsGet(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    if (args.len == 0) return JSValue.null_val;

    const target_key = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.null_val,
    };

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.null_val).toObject() orelse return JSValue.null_val;
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.null_val).toObject() orelse return JSValue.null_val;

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    for (keys_list.items, 0..) |k_val, idx| {
        if (k_val.isString()) {
            const k_str = vm.atom_table.get(k_val.toStringAtom());
            if (std.mem.eql(u8, k_str, target_key)) {
                if (idx < vals_list.items.len) {
                    return vals_list.items[idx];
                }
                return JSValue.null_val;
            }
        }
    }
    return JSValue.null_val;
}

fn nativeUrlSearchParamsGetAll(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));
    if (args.len == 0) return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));

    const target_key = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.fromObject(try createArray(vm, &[_]JSValue{})),
    };

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}))).toObject() orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}))).toObject() orelse return JSValue.fromObject(try createArray(vm, &[_]JSValue{}));

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    var matched: std.ArrayList(JSValue) = .empty;
    defer matched.deinit(vm.allocator);

    for (keys_list.items, 0..) |k_val, idx| {
        if (k_val.isString()) {
            const k_str = vm.atom_table.get(k_val.toStringAtom());
            if (std.mem.eql(u8, k_str, target_key)) {
                if (idx < vals_list.items.len) {
                    try matched.append(vm.allocator, vals_list.items[idx]);
                }
            }
        }
    }
    return JSValue.fromObject(try createArray(vm, matched.items));
}

fn nativeUrlSearchParamsHas(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const val = try nativeUrlSearchParamsGet(ctx, this_val, args);
    return JSValue.fromBoolean(!val.isNull());
}

fn nativeUrlSearchParamsAppend(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0) return JSValue.undefined_val;

    var k_buf: [128]u8 = undefined;
    const k_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&k_buf, "{d}", .{args[0].toInt32()}) catch "0",
        else => "key",
    };

    var v_buf: [128]u8 = undefined;
    const v_str = if (args.len > 1) switch (args[1].getType()) {
        .String => vm.atom_table.get(args[1].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&v_buf, "{d}", .{args[1].toInt32()}) catch "0",
        else => "",
    } else "";

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    try keys_list.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(k_str)));
    try vals_list.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(v_str)));

    const new_keys_arr = try createArray(vm, keys_list.items);
    const new_vals_arr = try createArray(vm, vals_list.items);
    try inst.setProperty(vm.allocator, keys_atom, JSValue.fromObject(new_keys_arr));
    try inst.setProperty(vm.allocator, vals_atom, JSValue.fromObject(new_vals_arr));

    return JSValue.undefined_val;
}

fn nativeUrlSearchParamsDelete(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0) return JSValue.undefined_val;

    const target_key = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    var new_k: std.ArrayList(JSValue) = .empty;
    defer new_k.deinit(vm.allocator);
    var new_v: std.ArrayList(JSValue) = .empty;
    defer new_v.deinit(vm.allocator);

    for (keys_list.items, 0..) |k_val, idx| {
        if (k_val.isString()) {
            const k_str = vm.atom_table.get(k_val.toStringAtom());
            if (std.mem.eql(u8, k_str, target_key)) continue;
        }
        try new_k.append(vm.allocator, k_val);
        if (idx < vals_list.items.len) {
            try new_v.append(vm.allocator, vals_list.items[idx]);
        }
    }

    const new_keys_arr = try createArray(vm, new_k.items);
    const new_vals_arr = try createArray(vm, new_v.items);
    try inst.setProperty(vm.allocator, keys_atom, JSValue.fromObject(new_keys_arr));
    try inst.setProperty(vm.allocator, vals_atom, JSValue.fromObject(new_vals_arr));

    return JSValue.undefined_val;
}

fn nativeUrlSearchParamsSet(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0) return JSValue.undefined_val;

    var k_buf: [128]u8 = undefined;
    const k_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&k_buf, "{d}", .{args[0].toInt32()}) catch "0",
        else => "key",
    };

    var v_buf: [128]u8 = undefined;
    const v_str = if (args.len > 1) switch (args[1].getType()) {
        .String => vm.atom_table.get(args[1].toStringAtom()),
        .Int32 => std.fmt.bufPrint(&v_buf, "{d}", .{args[1].toInt32()}) catch "0",
        else => "",
    } else "";

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    var new_k: std.ArrayList(JSValue) = .empty;
    defer new_k.deinit(vm.allocator);
    var new_v: std.ArrayList(JSValue) = .empty;
    defer new_v.deinit(vm.allocator);

    var found = false;
    for (keys_list.items, 0..) |k_val, idx| {
        if (k_val.isString()) {
            const cur_k_str = vm.atom_table.get(k_val.toStringAtom());
            if (std.mem.eql(u8, cur_k_str, k_str)) {
                if (!found) {
                    try new_k.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(k_str)));
                    try new_v.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(v_str)));
                    found = true;
                }
                continue;
            }
        }
        try new_k.append(vm.allocator, k_val);
        if (idx < vals_list.items.len) {
            try new_v.append(vm.allocator, vals_list.items[idx]);
        }
    }

    if (!found) {
        try new_k.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(k_str)));
        try new_v.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(v_str)));
    }

    const new_keys_arr = try createArray(vm, new_k.items);
    const new_vals_arr = try createArray(vm, new_v.items);
    try inst.setProperty(vm.allocator, keys_atom, JSValue.fromObject(new_keys_arr));
    try inst.setProperty(vm.allocator, vals_atom, JSValue.fromObject(new_vals_arr));

    return JSValue.undefined_val;
}

fn nativeUrlSearchParamsToString(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));

    const keys_atom = try vm.atom_table.intern("_keys");
    const vals_atom = try vm.atom_table.intern("_values");
    const keys_obj = (inst.getProperty(keys_atom) orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""))).toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    const vals_obj = (inst.getProperty(vals_atom) orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""))).toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    try getArrayElements(vm, keys_obj, &keys_list);

    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);
    try getArrayElements(vm, vals_obj, &vals_list);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    for (keys_list.items, 0..) |k_val, idx| {
        if (!k_val.isString()) continue;
        if (out.items.len > 0) try out.append(vm.allocator, '&');
        try out.appendSlice(vm.allocator, vm.atom_table.get(k_val.toStringAtom()));
        try out.append(vm.allocator, '=');
        if (idx < vals_list.items.len and vals_list.items[idx].isString()) {
            try out.appendSlice(vm.allocator, vm.atom_table.get(vals_list.items[idx].toStringAtom()));
        }
    }

    const atom = try vm.atom_table.intern(out.items);
    return JSValue.fromStringAtom(atom);
}

// WHATWG URL implementation
fn nativeUrlConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;

    const input_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };

    var resolved_url_str: []u8 = undefined;
    var needs_free_resolved = false;
    defer {
        if (needs_free_resolved) vm.allocator.free(resolved_url_str);
    }

    if (args.len > 1 and args[1].isString()) {
        const base_str = vm.atom_table.get(args[1].toStringAtom());
        var base_url = try URL.parse(vm.allocator, base_str);
        defer base_url.deinit();

        var res_url = try base_url.resolve(vm.allocator, input_str);
        defer res_url.deinit();

        resolved_url_str = try res_url.serialize(vm.allocator);
        needs_free_resolved = true;
    } else {
        resolved_url_str = @constCast(input_str);
        needs_free_resolved = false;
    }

    var parsed = try URL.parse(vm.allocator, resolved_url_str);
    defer parsed.deinit();

    const inst = try vm.gc.allocateObject(null);

    // href
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("href"), JSValue.fromStringAtom(try vm.atom_table.intern(resolved_url_str)));

    // origin
    const origin_str = try parsed.origin(vm.allocator);
    defer vm.allocator.free(origin_str);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("origin"), JSValue.fromStringAtom(try vm.atom_table.intern(origin_str)));

    // protocol
    var proto_buf: [32]u8 = undefined;
    const proto_str = std.fmt.bufPrint(&proto_buf, "{s}:", .{parsed.scheme}) catch "http:";
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("protocol"), JSValue.fromStringAtom(try vm.atom_table.intern(proto_str)));

    // host & hostname
    var host_buf: [256]u8 = undefined;
    const host_str = if (parsed.port != 80 and parsed.port != 443 and parsed.port != 0)
        std.fmt.bufPrint(&host_buf, "{s}:{d}", .{ parsed.host, parsed.port }) catch parsed.host
    else
        parsed.host;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("host"), JSValue.fromStringAtom(try vm.atom_table.intern(host_str)));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("hostname"), JSValue.fromStringAtom(try vm.atom_table.intern(parsed.host)));

    // port
    var port_buf: [16]u8 = undefined;
    const port_str = if (parsed.port != 80 and parsed.port != 443 and parsed.port != 0)
        std.fmt.bufPrint(&port_buf, "{d}", .{parsed.port}) catch ""
    else
        "";
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("port"), JSValue.fromStringAtom(try vm.atom_table.intern(port_str)));

    // pathname
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("pathname"), JSValue.fromStringAtom(try vm.atom_table.intern(parsed.path)));

    // search
    var search_buf = std.ArrayList(u8).empty;
    defer search_buf.deinit(vm.allocator);
    if (parsed.query) |q| {
        if (q.len > 0) {
            try search_buf.append(vm.allocator, '?');
            try search_buf.appendSlice(vm.allocator, q);
        }
    }
    const search_str = search_buf.items;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("search"), JSValue.fromStringAtom(try vm.atom_table.intern(search_str)));

    // hash
    var hash_buf = std.ArrayList(u8).empty;
    defer hash_buf.deinit(vm.allocator);
    if (parsed.fragment) |f| {
        if (f.len > 0) {
            try hash_buf.append(vm.allocator, '#');
            try hash_buf.appendSlice(vm.allocator, f);
        }
    }
    const hash_str = hash_buf.items;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("hash"), JSValue.fromStringAtom(try vm.atom_table.intern(hash_str)));

    // searchParams
    const search_atom = try vm.atom_table.intern(search_str);
    const params_val = try nativeUrlSearchParamsConstructor(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{JSValue.fromStringAtom(search_atom)});
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("searchParams"), params_val);

    // toString
    const to_str_fn = try vm.gc.allocateFunction(null, nativeUrlToString, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("toString"), JSValue.fromObject(to_str_fn));

    return JSValue.fromObject(inst);
}

fn nativeUrlToString(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const obj = this_val.toObject() orelse return JSValue.undefined_val;
    const href_atom = try vm.atom_table.intern("href");
    return obj.getProperty(href_atom) orelse JSValue.undefined_val;
}

var g_blob_counter: u64 = 1;

fn nativeUrlCreateObjectURL(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    var buf: [64]u8 = undefined;
    const count = g_blob_counter;
    g_blob_counter += 1;
    const url_str = std.fmt.bufPrint(&buf, "blob:davoth/{x}", .{count}) catch "blob:davoth/1";
    const atom = try vm.atom_table.intern(url_str);
    return JSValue.fromStringAtom(atom);
}

fn nativeUrlRevokeObjectURL(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeBlobConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const blob = try vm.gc.allocateObject(null);

    var mime_type: []const u8 = "";
    if (args.len > 1 and args[1].isObject()) {
        const opt = args[1].toObject().?;
        if (opt.getProperty(try vm.atom_table.intern("type"))) |type_val| {
            if (type_val.isString()) {
                mime_type = vm.atom_table.get(type_val.toStringAtom());
            }
        }
    }

    var total_size: usize = 0;
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(vm.allocator);

    if (args.len > 0 and args[0].isObject()) {
        const parts_obj = args[0].toObject().?;
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, parts_obj, &items);
        for (items.items) |item| {
            if (item.isString()) {
                const s = vm.atom_table.get(item.toStringAtom());
                try content.appendSlice(vm.allocator, s);
                total_size += s.len;
            }
        }
    }

    try blob.setProperty(vm.allocator, try vm.atom_table.intern("size"), JSValue.fromInt32(@intCast(total_size)));
    try blob.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern(mime_type)));
    try blob.setProperty(vm.allocator, try vm.atom_table.intern("_data"), JSValue.fromStringAtom(try vm.atom_table.intern(content.items)));

    const text_fn = try vm.gc.allocateFunction(null, nativeBlobText, @ptrCast(vm));
    try blob.setProperty(vm.allocator, try vm.atom_table.intern("text"), JSValue.fromObject(text_fn));

    return JSValue.fromObject(blob);
}

fn nativeBlobText(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    const data_atom = try vm.atom_table.intern("_data");
    return inst.getProperty(data_atom) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

// AbortSignal and AbortController Web APIs
fn nativeAbortSignalConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("aborted"), JSValue.false_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("reason"), JSValue.undefined_val);

    const abort_fn = try vm.gc.allocateFunction(null, nativeAbortSignalAbortMethod, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_abortInternal"), JSValue.fromObject(abort_fn));

    return JSValue.fromObject(inst);
}

fn nativeAbortSignalAbortMethod(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("aborted"), JSValue.true_val);
    if (args.len > 0) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("reason"), args[0]);
    } else {
        const def_reason = try vm.atom_table.intern("AbortError");
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("reason"), JSValue.fromStringAtom(def_reason));
    }
    return JSValue.undefined_val;
}

fn nativeAbortControllerConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);

    const sig_val = try nativeAbortSignalConstructor(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{});
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("signal"), sig_val);

    const abort_fn = try vm.gc.allocateFunction(null, nativeAbortControllerAbort, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("abort"), JSValue.fromObject(abort_fn));

    return JSValue.fromObject(inst);
}

fn nativeAbortControllerAbort(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const sig_atom = try vm.atom_table.intern("signal");
    const sig_val = inst.getProperty(sig_atom) orelse return JSValue.undefined_val;
    _ = try nativeAbortSignalAbortMethod(ctx, sig_val, args);
    return JSValue.undefined_val;
}

fn nativeAbortSignalStaticAbort(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const sig_val = try nativeAbortSignalConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    _ = try nativeAbortSignalAbortMethod(ctx, sig_val, args);
    return sig_val;
}

fn nativeAbortSignalStaticTimeout(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    _ = args;
    return nativeAbortSignalConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
}

fn collectFormControls(vm: *VM, elem: *JSObject, keys: *std.ArrayList(JSValue), vals: *std.ArrayList(JSValue)) anyerror!void {
    const tag_val = elem.getProperty(try vm.atom_table.intern("tagName")) orelse JSValue.null_val;
    if (tag_val.isString()) {
        const tag = vm.atom_table.get(tag_val.toStringAtom());
        if (std.ascii.eqlIgnoreCase(tag, "input") or
            std.ascii.eqlIgnoreCase(tag, "textarea") or
            std.ascii.eqlIgnoreCase(tag, "select") or
            std.ascii.eqlIgnoreCase(tag, "button"))
        {
            var is_disabled = false;
            if (elem.getProperty(try vm.atom_table.intern("disabled"))) |dv| {
                is_disabled = dv.toBoolean();
            }
            if (!is_disabled) {
                var name_str: ?[]const u8 = null;
                if (elem.getProperty(try vm.atom_table.intern("name"))) |nv| {
                    if (nv.isString()) {
                        const s = vm.atom_table.get(nv.toStringAtom());
                        if (s.len > 0) name_str = s;
                    }
                }
                if (name_str == null) {
                    if (jsElementHasAttribute(vm, elem, "name")) {
                        const nattr = try nativeElementGetAttribute(@ptrCast(vm), JSValue.fromObject(elem), &[_]JSValue{JSValue.fromStringAtom(try vm.atom_table.intern("name"))});
                        if (nattr.isString()) {
                            const s = vm.atom_table.get(nattr.toStringAtom());
                            if (s.len > 0) name_str = s;
                        }
                    }
                }

                if (name_str) |n| {
                    var val_val = elem.getProperty(try vm.atom_table.intern("value")) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
                    if (jsElementHasAttribute(vm, elem, "value") and val_val.isString() and vm.atom_table.get(val_val.toStringAtom()).len == 0) {
                        val_val = try nativeElementGetAttribute(@ptrCast(vm), JSValue.fromObject(elem), &[_]JSValue{JSValue.fromStringAtom(try vm.atom_table.intern("value"))});
                    }
                    const name_atom = try vm.atom_table.intern(n);
                    try keys.append(vm.allocator, JSValue.fromStringAtom(name_atom));
                    try vals.append(vm.allocator, val_val);
                }
            }
        }
    }

    const children_atom = try vm.atom_table.intern("_children");
    if (elem.getProperty(children_atom)) |ch_val| {
        if (ch_val.toObject()) |arr_obj| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, arr_obj, &items);
            for (items.items) |child_val| {
                if (child_val.toObject()) |child_obj| {
                    try collectFormControls(vm, child_obj, keys, vals);
                }
            }
        }
    }
}

// FormData Web API
fn nativeFormDataConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);

    var keys_list: std.ArrayList(JSValue) = .empty;
    defer keys_list.deinit(vm.allocator);
    var vals_list: std.ArrayList(JSValue) = .empty;
    defer vals_list.deinit(vm.allocator);

    if (args.len > 0 and args[0].isObject()) {
        const root = args[0].toObject().?;
        try collectFormControls(vm, root, &keys_list, &vals_list);
    }

    const keys_arr = try createArray(vm, keys_list.items);
    const vals_arr = try createArray(vm, vals_list.items);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_keys"), JSValue.fromObject(keys_arr));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_values"), JSValue.fromObject(vals_arr));

    const append_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsAppend, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("append"), JSValue.fromObject(append_fn));

    const get_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsGet, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("get"), JSValue.fromObject(get_fn));

    const get_all_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsGetAll, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getAll"), JSValue.fromObject(get_all_fn));

    const has_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsHas, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("has"), JSValue.fromObject(has_fn));

    const set_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsSet, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("set"), JSValue.fromObject(set_fn));

    const delete_fn = try vm.gc.allocateFunction(null, nativeUrlSearchParamsDelete, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("delete"), JSValue.fromObject(delete_fn));

    return JSValue.fromObject(inst);
}

// WebSocket Web API
fn nativeWebSocketConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);

    const url_str = if (args.len > 0 and args[0].isString())
        vm.atom_table.get(args[0].toStringAtom())
    else
        "ws://localhost";
    const url_atom = try vm.atom_table.intern(url_str);

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("url"), JSValue.fromStringAtom(url_atom));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("readyState"), JSValue.fromInt32(1)); // OPEN
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("bufferedAmount"), JSValue.fromInt32(0));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("protocol"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("extensions"), JSValue.fromStringAtom(try vm.atom_table.intern("")));

    // ReadyState constants
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("CONNECTING"), JSValue.fromInt32(0));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("OPEN"), JSValue.fromInt32(1));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("CLOSING"), JSValue.fromInt32(2));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("CLOSED"), JSValue.fromInt32(3));

    const send_fn = try vm.gc.allocateFunction(null, nativeWebSocketSend, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("send"), JSValue.fromObject(send_fn));

    const close_fn = try vm.gc.allocateFunction(null, nativeWebSocketClose, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("close"), JSValue.fromObject(close_fn));

    return JSValue.fromObject(inst);
}

fn nativeWebSocketSend(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeWebSocketClose(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("readyState"), JSValue.fromInt32(3)); // CLOSED
    return JSValue.undefined_val;
}

// CSSStyleDeclaration and CSSOM helpers
fn createCSSStyleDeclaration(vm: *VM) !*JSObject {
    const style_obj = try vm.gc.allocateObject(null);
    const set_fn = try vm.gc.allocateFunction(null, nativeStyleSetProperty, @ptrCast(vm));
    try style_obj.setProperty(vm.allocator, try vm.atom_table.intern("setProperty"), JSValue.fromObject(set_fn));
    const get_fn = try vm.gc.allocateFunction(null, nativeStyleGetPropertyValue, @ptrCast(vm));
    try style_obj.setProperty(vm.allocator, try vm.atom_table.intern("getPropertyValue"), JSValue.fromObject(get_fn));
    const rem_fn = try vm.gc.allocateFunction(null, nativeStyleRemoveProperty, @ptrCast(vm));
    try style_obj.setProperty(vm.allocator, try vm.atom_table.intern("removeProperty"), JSValue.fromObject(rem_fn));
    const prio_fn = try vm.gc.allocateFunction(null, nativeStyleGetPropertyPriority, @ptrCast(vm));
    try style_obj.setProperty(vm.allocator, try vm.atom_table.intern("getPropertyPriority"), JSValue.fromObject(prio_fn));
    try style_obj.setProperty(vm.allocator, try vm.atom_table.intern("cssText"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    return style_obj;
}

fn nativeStyleSetProperty(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2 or !args[0].isString()) return JSValue.undefined_val;

    const prop_name = vm.atom_table.get(args[0].toStringAtom());
    const prop_atom = try vm.atom_table.intern(prop_name);
    try inst.setProperty(vm.allocator, prop_atom, args[1]);

    if (std.mem.indexOfScalar(u8, prop_name, '-')) |_| {
        var camel_buf: [128]u8 = undefined;
        var c_idx: usize = 0;
        var cap_next = false;
        for (prop_name) |ch| {
            if (ch == '-') {
                cap_next = true;
            } else {
                if (c_idx < camel_buf.len) {
                    camel_buf[c_idx] = if (cap_next) std.ascii.toUpper(ch) else ch;
                    c_idx += 1;
                }
                cap_next = false;
            }
        }
        if (c_idx > 0) {
            const camel_atom = try vm.atom_table.intern(camel_buf[0..c_idx]);
            try inst.setProperty(vm.allocator, camel_atom, args[1]);
        }
    }

    return JSValue.undefined_val;
}

fn nativeStyleGetPropertyValue(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    if (args.len == 0 or !args[0].isString()) return JSValue.fromStringAtom(try vm.atom_table.intern(""));

    const prop_name = vm.atom_table.get(args[0].toStringAtom());
    const prop_atom = try vm.atom_table.intern(prop_name);
    if (inst.getProperty(prop_atom)) |val| {
        if (val.isString()) return val;
    }

    if (std.mem.indexOfScalar(u8, prop_name, '-')) |_| {
        var camel_buf: [128]u8 = undefined;
        var c_idx: usize = 0;
        var cap_next = false;
        for (prop_name) |ch| {
            if (ch == '-') {
                cap_next = true;
            } else {
                if (c_idx < camel_buf.len) {
                    camel_buf[c_idx] = if (cap_next) std.ascii.toUpper(ch) else ch;
                    c_idx += 1;
                }
                cap_next = false;
            }
        }
        if (c_idx > 0) {
            const camel_atom = try vm.atom_table.intern(camel_buf[0..c_idx]);
            if (inst.getProperty(camel_atom)) |val| {
                if (val.isString()) return val;
            }
        }
    }

    // Try parsing out of cssText if set
    if (inst.getProperty(try vm.atom_table.intern("cssText"))) |ct_val| {
        if (ct_val.isString()) {
            const ct_str = vm.atom_table.get(ct_val.toStringAtom());
            var decl_it = std.mem.splitScalar(u8, ct_str, ';');
            while (decl_it.next()) |decl| {
                if (std.mem.indexOfScalar(u8, decl, ':')) |colon| {
                    const d_name = std.mem.trim(u8, decl[0..colon], " \t\r\n");
                    const d_val = std.mem.trim(u8, decl[colon + 1 ..], " \t\r\n");
                    if (std.ascii.eqlIgnoreCase(d_name, prop_name)) {
                        return JSValue.fromStringAtom(try vm.atom_table.intern(d_val));
                    }
                }
            }
        }
    }

    return JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeStyleRemoveProperty(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    if (args.len == 0 or !args[0].isString()) return JSValue.fromStringAtom(try vm.atom_table.intern(""));

    const prop_name = vm.atom_table.get(args[0].toStringAtom());
    const prop_atom = try vm.atom_table.intern(prop_name);
    const old_val = inst.getProperty(prop_atom) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
    try inst.setProperty(vm.allocator, prop_atom, JSValue.fromStringAtom(try vm.atom_table.intern("")));
    return if (old_val.isString()) old_val else JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeStyleGetPropertyPriority(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeFormSubmit(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (!this_val.isObject()) return JSValue.undefined_val;

    const ev_opts = try vm.gc.allocateObject(null);
    try ev_opts.setProperty(vm.allocator, try vm.atom_table.intern("bubbles"), JSValue.true_val);
    try ev_opts.setProperty(vm.allocator, try vm.atom_table.intern("cancelable"), JSValue.true_val);

    const submit_ev = try nativeSubmitEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try vm.atom_table.intern("submit")),
        JSValue.fromObject(ev_opts),
    });
    _ = try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{submit_ev});
    return JSValue.undefined_val;
}

fn nativeFormReset(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (!this_val.isObject()) return JSValue.undefined_val;

    const reset_ev = try nativeEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try vm.atom_table.intern("reset")),
    });
    _ = try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{reset_ev});
    return JSValue.undefined_val;
}

// DOM Element and Document Web APIs
fn createJsElement(vm: *VM, tag: []const u8) !*JSObject {
    const inst = try vm.gc.allocateObject(null);
    const tag_atom = try vm.atom_table.intern(tag);

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("tagName"), JSValue.fromStringAtom(tag_atom));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(tag_atom));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(1));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("id"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("className"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("parentElement"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("firstChild"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("lastChild"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("firstElementChild"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("lastElementChild"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("previousSibling"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nextSibling"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("previousElementSibling"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nextElementSibling"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("childElementCount"), JSValue.fromInt32(0));

    const children_arr = try createArray(vm, &[_]JSValue{});
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_children"), JSValue.fromObject(children_arr));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("children"), JSValue.fromObject(children_arr));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("childNodes"), JSValue.fromObject(children_arr));

    const style_obj = try createCSSStyleDeclaration(vm);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("style"), JSValue.fromObject(style_obj));

    const dataset_obj = try vm.gc.allocateObject(null);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("dataset"), JSValue.fromObject(dataset_obj));

    // classList
    const class_list_obj = try vm.gc.allocateObject(null);
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("_elem"), JSValue.fromObject(inst));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("length"), JSValue.fromInt32(0));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("value"), JSValue.fromStringAtom(try vm.atom_table.intern("")));

    const cl_add_fn = try vm.gc.allocateFunction(null, nativeClassListAdd, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("add"), JSValue.fromObject(cl_add_fn));

    const cl_remove_fn = try vm.gc.allocateFunction(null, nativeClassListRemove, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("remove"), JSValue.fromObject(cl_remove_fn));

    const cl_contains_fn = try vm.gc.allocateFunction(null, nativeClassListContains, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("contains"), JSValue.fromObject(cl_contains_fn));

    const cl_toggle_fn = try vm.gc.allocateFunction(null, nativeClassListToggle, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("toggle"), JSValue.fromObject(cl_toggle_fn));

    const cl_item_fn = try vm.gc.allocateFunction(null, nativeClassListItem, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("item"), JSValue.fromObject(cl_item_fn));

    const cl_replace_fn = try vm.gc.allocateFunction(null, nativeClassListReplace, @ptrCast(vm));
    try class_list_obj.setProperty(vm.allocator, try vm.atom_table.intern("replace"), JSValue.fromObject(cl_replace_fn));

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("classList"), JSValue.fromObject(class_list_obj));

    const empty_attrs = try createArray(vm, &[_]JSValue{});
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("_attrs"), JSValue.fromObject(empty_attrs));

    const has_attrs_fn = try vm.gc.allocateFunction(null, nativeElementHasAttributes, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("hasAttributes"), JSValue.fromObject(has_attrs_fn));

    const get_attr_names_fn = try vm.gc.allocateFunction(null, nativeElementGetAttributeNames, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getAttributeNames"), JSValue.fromObject(get_attr_names_fn));

    const toggle_attr_fn = try vm.gc.allocateFunction(null, nativeElementToggleAttribute, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("toggleAttribute"), JSValue.fromObject(toggle_attr_fn));

    const replace_with_fn = try vm.gc.allocateFunction(null, nativeElementReplaceWith, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("replaceWith"), JSValue.fromObject(replace_with_fn));

    // Element methods
    const get_attr_fn = try vm.gc.allocateFunction(null, nativeElementGetAttribute, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getAttribute"), JSValue.fromObject(get_attr_fn));

    const set_attr_fn = try vm.gc.allocateFunction(null, nativeElementSetAttribute, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("setAttribute"), JSValue.fromObject(set_attr_fn));

    const append_child_fn = try vm.gc.allocateFunction(null, nativeElementAppendChild, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("appendChild"), JSValue.fromObject(append_child_fn));

    const remove_child_fn = try vm.gc.allocateFunction(null, nativeElementRemoveChild, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("removeChild"), JSValue.fromObject(remove_child_fn));

    const has_attr_fn = try vm.gc.allocateFunction(null, nativeElementHasAttribute, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("hasAttribute"), JSValue.fromObject(has_attr_fn));

    const rem_attr_fn = try vm.gc.allocateFunction(null, nativeElementRemoveAttribute, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("removeAttribute"), JSValue.fromObject(rem_attr_fn));

    const elem_qs_fn = try vm.gc.allocateFunction(null, nativeElementQuerySelector, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("querySelector"), JSValue.fromObject(elem_qs_fn));

    const elem_qsa_fn = try vm.gc.allocateFunction(null, nativeElementQuerySelectorAll, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("querySelectorAll"), JSValue.fromObject(elem_qsa_fn));

    const matches_fn = try vm.gc.allocateFunction(null, nativeElementMatches, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("matches"), JSValue.fromObject(matches_fn));

    const closest_fn = try vm.gc.allocateFunction(null, nativeElementClosest, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("closest"), JSValue.fromObject(closest_fn));

    const ins_before_fn = try vm.gc.allocateFunction(null, nativeElementInsertBefore, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("insertBefore"), JSValue.fromObject(ins_before_fn));

    const click_fn = try vm.gc.allocateFunction(null, nativeElementClick, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("click"), JSValue.fromObject(click_fn));

    const remove_fn = try vm.gc.allocateFunction(null, nativeElementRemove, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("remove"), JSValue.fromObject(remove_fn));

    const contains_fn = try vm.gc.allocateFunction(null, nativeElementContains, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("contains"), JSValue.fromObject(contains_fn));

    const clone_node_fn = try vm.gc.allocateFunction(null, nativeElementCloneNode, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("cloneNode"), JSValue.fromObject(clone_node_fn));

    const rep_child_fn = try vm.gc.allocateFunction(null, nativeElementReplaceChild, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("replaceChild"), JSValue.fromObject(rep_child_fn));

    const get_by_tag_fn = try vm.gc.allocateFunction(null, nativeElementGetElementsByTagName, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getElementsByTagName"), JSValue.fromObject(get_by_tag_fn));

    const get_by_cls_fn = try vm.gc.allocateFunction(null, nativeElementGetElementsByClassName, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getElementsByClassName"), JSValue.fromObject(get_by_cls_fn));

    const add_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetAddEventListener, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("addEventListener"), JSValue.fromObject(add_ev_fn));

    const rem_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetRemoveEventListener, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("removeEventListener"), JSValue.fromObject(rem_ev_fn));

    const disp_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetDispatchEvent, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("dispatchEvent"), JSValue.fromObject(disp_ev_fn));

    const get_bcr_fn = try vm.gc.allocateFunction(null, nativeElementGetBoundingClientRect, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getBoundingClientRect"), JSValue.fromObject(get_bcr_fn));

    const get_cr_fn = try vm.gc.allocateFunction(null, nativeElementGetClientRects, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("getClientRects"), JSValue.fromObject(get_cr_fn));

    const append_fn = try vm.gc.allocateFunction(null, nativeElementAppend, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("append"), JSValue.fromObject(append_fn));

    const prepend_fn = try vm.gc.allocateFunction(null, nativeElementPrepend, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("prepend"), JSValue.fromObject(prepend_fn));

    const before_fn = try vm.gc.allocateFunction(null, nativeElementBefore, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("before"), JSValue.fromObject(before_fn));

    const after_fn = try vm.gc.allocateFunction(null, nativeElementAfter, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("after"), JSValue.fromObject(after_fn));

    const focus_fn = try vm.gc.allocateFunction(null, nativeElementFocus, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("focus"), JSValue.fromObject(focus_fn));

    const blur_fn = try vm.gc.allocateFunction(null, nativeElementBlur, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("blur"), JSValue.fromObject(blur_fn));

    const scroll_fn = try vm.gc.allocateFunction(null, nativeElementScrollIntoView, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("scrollIntoView"), JSValue.fromObject(scroll_fn));

    const is_same_fn = try vm.gc.allocateFunction(null, nativeElementIsSameNode, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("isSameNode"), JSValue.fromObject(is_same_fn));

    const is_equal_fn = try vm.gc.allocateFunction(null, nativeElementIsEqualNode, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("isEqualNode"), JSValue.fromObject(is_equal_fn));

    const comp_pos_fn = try vm.gc.allocateFunction(null, nativeElementCompareDocumentPosition, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("compareDocumentPosition"), JSValue.fromObject(comp_pos_fn));

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("innerHTML"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("outerHTML"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), JSValue.fromStringAtom(try vm.atom_table.intern("")));

    if (std.ascii.eqlIgnoreCase(tag, "template")) {
        const frag = try nativeDocumentCreateDocumentFragment(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{});
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("content"), frag);
    }

    // Form element default properties
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("value"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("name"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("checked"), JSValue.false_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("disabled"), JSValue.false_val);

    if (std.ascii.eqlIgnoreCase(tag, "input")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern("text")));
    } else if (std.ascii.eqlIgnoreCase(tag, "button")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern("submit")));
    } else if (std.ascii.eqlIgnoreCase(tag, "form")) {
        const form_submit_fn = try vm.gc.allocateFunction(null, nativeFormSubmit, @ptrCast(vm));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("submit"), JSValue.fromObject(form_submit_fn));
        const form_reset_fn = try vm.gc.allocateFunction(null, nativeFormReset, @ptrCast(vm));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("reset"), JSValue.fromObject(form_reset_fn));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("method"), JSValue.fromStringAtom(try vm.atom_table.intern("get")));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("action"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("target"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("enctype"), JSValue.fromStringAtom(try vm.atom_table.intern("application/x-www-form-urlencoded")));
    }

    if (std.ascii.eqlIgnoreCase(tag, "canvas")) {
        const get_ctx_fn = try vm.gc.allocateFunction(null, nativeCanvasGetContext, @ptrCast(vm));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("getContext"), JSValue.fromObject(get_ctx_fn));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("width"), JSValue.fromInt32(300));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("height"), JSValue.fromInt32(150));
        const to_data_url_fn = try vm.gc.allocateFunction(null, nativeCanvasToDataURL, @ptrCast(vm));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("toDataURL"), JSValue.fromObject(to_data_url_fn));
        const to_blob_fn = try vm.gc.allocateFunction(null, nativeCanvasToBlob, @ptrCast(vm));
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("toBlob"), JSValue.fromObject(to_blob_fn));
    }

    return inst;
}

fn syncClassListProperties(vm: *VM, inst: *JSObject, items: []const JSValue) anyerror!void {
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("length"), JSValue.fromInt32(@intCast(items.len)));

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    for (items, 0..) |it, idx| {
        if (it.isString()) {
            if (idx > 0) try buf.append(vm.allocator, ' ');
            try buf.appendSlice(vm.allocator, vm.atom_table.get(it.toStringAtom()));
        }
    }

    const val_str = try vm.atom_table.intern(buf.items);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("value"), JSValue.fromStringAtom(val_str));

    if (inst.getProperty(try vm.atom_table.intern("_elem"))) |el_val| {
        if (el_val.toObject()) |el_obj| {
            try el_obj.setProperty(vm.allocator, try vm.atom_table.intern("className"), JSValue.fromStringAtom(val_str));
            try el_obj.setProperty(vm.allocator, try vm.atom_table.intern("class"), JSValue.fromStringAtom(val_str));

            const attrs_atom = try vm.atom_table.intern("_attrs");
            if (el_obj.getProperty(attrs_atom)) |val| {
                if (val.toObject()) |arr| {
                    var list: std.ArrayList(JSValue) = .empty;
                    defer list.deinit(vm.allocator);
                    try getArrayElements(vm, arr, &list);
                    const class_atom = try vm.atom_table.intern("class");
                    var class_idx: ?usize = null;
                    for (list.items, 0..) |it, i| {
                        if (it.isString() and std.mem.eql(u8, vm.atom_table.get(it.toStringAtom()), "class")) {
                            class_idx = i;
                            break;
                        }
                    }

                    if (items.len > 0 and class_idx == null) {
                        try list.append(vm.allocator, JSValue.fromStringAtom(class_atom));
                        const new_arr = try createArray(vm, list.items);
                        try el_obj.setProperty(vm.allocator, attrs_atom, JSValue.fromObject(new_arr));
                    } else if (items.len == 0 and class_idx != null) {
                        _ = list.orderedRemove(class_idx.?);
                        const new_arr = try createArray(vm, list.items);
                        try el_obj.setProperty(vm.allocator, attrs_atom, JSValue.fromObject(new_arr));
                    }
                }
            }
        }
    }
}

fn nativeClassListItem(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    if (args.len == 0 or !args[0].isNumber()) return JSValue.null_val;
    const idx = args[0].toInt32();
    if (idx < 0) return JSValue.null_val;

    const tokens_atom = try vm.atom_table.intern("_tokens");
    if (inst.getProperty(tokens_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            if (@as(usize, @intCast(idx)) < list.items.len) {
                return list.items[@as(usize, @intCast(idx))];
            }
        }
    }
    return JSValue.null_val;
}

fn nativeClassListReplace(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    if (args.len < 2 or !args[0].isString() or !args[1].isString()) return JSValue.false_val;

    const old_tok = vm.atom_table.get(args[0].toStringAtom());
    const new_tok = args[1];
    const tokens_atom = try vm.atom_table.intern("_tokens");
    if (inst.getProperty(tokens_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);

            var found = false;
            for (list.items, 0..) |item, i| {
                if (item.isString() and std.mem.eql(u8, vm.atom_table.get(item.toStringAtom()), old_tok)) {
                    list.items[i] = new_tok;
                    found = true;
                    break;
                }
            }

            if (found) {
                const new_arr = try createArray(vm, list.items);
                try inst.setProperty(vm.allocator, tokens_atom, JSValue.fromObject(new_arr));
                try syncClassListProperties(vm, inst, list.items);
                return JSValue.true_val;
            }
        }
    }
    return JSValue.false_val;
}

fn nativeElementHasAttributes(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    const attrs_atom = try vm.atom_table.intern("_attrs");
    if (inst.getProperty(attrs_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            return if (list.items.len > 0) JSValue.true_val else JSValue.false_val;
        }
    }
    return JSValue.false_val;
}

fn nativeElementGetAttributeNames(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    const attrs_atom = try vm.atom_table.intern("_attrs");
    if (inst.getProperty(attrs_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            const copy_arr = try createArray(vm, list.items);
            return JSValue.fromObject(copy_arr);
        }
    }
    const empty_arr = try createArray(vm, &[_]JSValue{});
    return JSValue.fromObject(empty_arr);
}

fn nativeElementToggleAttribute(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.false_val;

    const attr_name = vm.atom_table.get(args[0].toStringAtom());
    const has = jsElementHasAttribute(vm, inst, attr_name);

    if (args.len > 1) {
        const force = args[1].toBoolean();
        if (force) {
            _ = try nativeElementSetAttribute(ctx, this_val, &[_]JSValue{ args[0], JSValue.fromStringAtom(try vm.atom_table.intern("")) });
            return JSValue.true_val;
        } else {
            _ = try nativeElementRemoveAttribute(ctx, this_val, &[_]JSValue{args[0]});
            return JSValue.false_val;
        }
    } else {
        if (has) {
            _ = try nativeElementRemoveAttribute(ctx, this_val, &[_]JSValue{args[0]});
            return JSValue.false_val;
        } else {
            _ = try nativeElementSetAttribute(ctx, this_val, &[_]JSValue{ args[0], JSValue.fromStringAtom(try vm.atom_table.intern("")) });
            return JSValue.true_val;
        }
    }
}

fn nativeElementReplaceWith(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const parent_val = inst.getProperty(try vm.atom_table.intern("parentNode")) orelse return JSValue.undefined_val;
    const parent_obj = parent_val.toObject() orelse return JSValue.undefined_val;

    const children_atom = try vm.atom_table.intern("_children");
    const ch_val = parent_obj.getProperty(children_atom) orelse return JSValue.undefined_val;
    const ch_arr = ch_val.toObject() orelse return JSValue.undefined_val;

    var items: std.ArrayList(JSValue) = .empty;
    defer items.deinit(vm.allocator);
    try getArrayElements(vm, ch_arr, &items);

    var new_items: std.ArrayList(JSValue) = .empty;
    defer new_items.deinit(vm.allocator);

    for (items.items) |it| {
        if (it.toObject()) |co| {
            if (co == inst) {
                for (args) |arg| {
                    if (arg.toObject()) |arg_obj| {
                        try arg_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), parent_val);
                        try new_items.append(vm.allocator, arg);
                    }
                }
            } else {
                try new_items.append(vm.allocator, it);
            }
        } else {
            try new_items.append(vm.allocator, it);
        }
    }

    const new_arr = try createArray(vm, new_items.items);
    try parent_obj.setProperty(vm.allocator, children_atom, JSValue.fromObject(new_arr));
    try updateElementTreeRelationships(vm, parent_obj);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);

    return JSValue.undefined_val;
}

fn nativeElementGetAttribute(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    if (args.len == 0) return JSValue.null_val;

    const attr_name = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.null_val,
    };

    const atom = vm.atom_table.map.get(attr_name) orelse return JSValue.null_val;
    return inst.getProperty(atom) orelse JSValue.null_val;
}

fn nativeElementSetAttribute(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2) return JSValue.undefined_val;

    const attr_name = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.undefined_val,
    };

    const atom = try vm.atom_table.intern(attr_name);
    try inst.setProperty(vm.allocator, atom, args[1]);

    const attrs_atom = try vm.atom_table.intern("_attrs");
    if (inst.getProperty(attrs_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            var exists = false;
            for (list.items) |it| {
                if (it.isString() and std.mem.eql(u8, vm.atom_table.get(it.toStringAtom()), attr_name)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                try list.append(vm.allocator, JSValue.fromStringAtom(atom));
                const new_arr = try createArray(vm, list.items);
                try inst.setProperty(vm.allocator, attrs_atom, JSValue.fromObject(new_arr));
            }
        }
    }

    if (std.mem.eql(u8, attr_name, "id")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("id"), args[1]);
    } else if (std.mem.eql(u8, attr_name, "checked")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("checked"), JSValue.true_val);
    } else if (std.mem.eql(u8, attr_name, "disabled")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("disabled"), JSValue.true_val);
    } else if (std.mem.eql(u8, attr_name, "class")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("className"), args[1]);
        if (args[1].isString()) {
            const cls_str = vm.atom_table.get(args[1].toStringAtom());
            if (inst.getProperty(try vm.atom_table.intern("classList"))) |cl_val| {
                if (cl_val.toObject()) |cl_obj| {
                    var tokens: std.ArrayList(JSValue) = .empty;
                    defer tokens.deinit(vm.allocator);
                    var it = std.mem.tokenizeScalar(u8, cls_str, ' ');
                    while (it.next()) |tok| {
                        if (tok.len > 0) {
                            try tokens.append(vm.allocator, JSValue.fromStringAtom(try vm.atom_table.intern(tok)));
                        }
                    }
                    const tok_arr = try createArray(vm, tokens.items);
                    try cl_obj.setProperty(vm.allocator, try vm.atom_table.intern("_tokens"), JSValue.fromObject(tok_arr));
                    try syncClassListProperties(vm, cl_obj, tokens.items);
                }
            }
        }
    }

    return JSValue.undefined_val;
}

fn updateElementTreeRelationships(vm: *VM, parent: *JSObject) !void {
    const children_atom = try vm.atom_table.intern("_children");
    const c_arr_val = parent.getProperty(children_atom) orelse return;
    const c_arr = c_arr_val.toObject() orelse return;

    var items: std.ArrayList(JSValue) = .empty;
    defer items.deinit(vm.allocator);
    try getArrayElements(vm, c_arr, &items);

    try parent.setProperty(vm.allocator, try vm.atom_table.intern("childNodes"), c_arr_val);

    if (items.items.len > 0) {
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("firstChild"), items.items[0]);
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("lastChild"), items.items[items.items.len - 1]);
    } else {
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("firstChild"), JSValue.null_val);
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("lastChild"), JSValue.null_val);
    }

    var elem_children: std.ArrayList(JSValue) = .empty;
    defer elem_children.deinit(vm.allocator);

    const nt_atom = try vm.atom_table.intern("nodeType");
    for (items.items) |it| {
        if (it.toObject()) |ch_obj| {
            if (ch_obj.getProperty(nt_atom)) |nt| {
                if (nt.toInt32() == 1) {
                    try elem_children.append(vm.allocator, it);
                }
            }
        }
    }

    const elem_children_arr = try createArray(vm, elem_children.items);
    try parent.setProperty(vm.allocator, try vm.atom_table.intern("children"), JSValue.fromObject(elem_children_arr));
    try parent.setProperty(vm.allocator, try vm.atom_table.intern("childElementCount"), JSValue.fromInt32(@intCast(elem_children.items.len)));

    if (elem_children.items.len > 0) {
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("firstElementChild"), elem_children.items[0]);
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("lastElementChild"), elem_children.items[elem_children.items.len - 1]);
    } else {
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("firstElementChild"), JSValue.null_val);
        try parent.setProperty(vm.allocator, try vm.atom_table.intern("lastElementChild"), JSValue.null_val);
    }

    for (items.items, 0..) |it, idx| {
        if (it.toObject()) |ch_obj| {
            const prev = if (idx > 0) items.items[idx - 1] else JSValue.null_val;
            const next = if (idx + 1 < items.items.len) items.items[idx + 1] else JSValue.null_val;
            try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("previousSibling"), prev);
            try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("nextSibling"), next);

            const p_nt = parent.getProperty(nt_atom) orelse JSValue.fromInt32(1);
            if (p_nt.toInt32() == 1) {
                try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentElement"), JSValue.fromObject(parent));
            } else {
                try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentElement"), JSValue.null_val);
            }
        }
    }

    for (elem_children.items, 0..) |it, idx| {
        if (it.toObject()) |ch_obj| {
            const prev_el = if (idx > 0) elem_children.items[idx - 1] else JSValue.null_val;
            const next_el = if (idx + 1 < elem_children.items.len) elem_children.items[idx + 1] else JSValue.null_val;
            try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("previousElementSibling"), prev_el);
            try ch_obj.setProperty(vm.allocator, try vm.atom_table.intern("nextElementSibling"), next_el);
        }
    }

    var text_buf: std.ArrayList(u8) = .empty;
    defer text_buf.deinit(vm.allocator);
    for (items.items) |it| {
        if (it.toObject()) |ch_obj| {
            if (ch_obj.getProperty(nt_atom)) |nt| {
                const nt_i = nt.toInt32();
                if (nt_i == 3 or nt_i == 1) {
                    if (ch_obj.getProperty(try vm.atom_table.intern("textContent"))) |tc| {
                        if (tc.isString()) {
                            try text_buf.appendSlice(vm.allocator, vm.atom_table.get(tc.toStringAtom()));
                        }
                    }
                }
            }
        }
    }
    const tc_atom = try vm.atom_table.intern(text_buf.items);
    try parent.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), JSValue.fromStringAtom(tc_atom));
}

fn nativeElementAppendChild(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.undefined_val;

    const child_obj = args[0].toObject().?;
    const children_atom = try vm.atom_table.intern("_children");
    const children_arr = (inst.getProperty(children_atom) orelse JSValue.undefined_val).toObject();
    if (children_arr) |c_arr| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, c_arr, &items);

        const nt_atom = try vm.atom_table.intern("nodeType");
        const is_frag = if (child_obj.getProperty(nt_atom)) |nt| nt.toInt32() == 11 else false;
        if (is_frag) {
            const frag_children_arr = (child_obj.getProperty(children_atom) orelse JSValue.undefined_val).toObject();
            if (frag_children_arr) |f_arr| {
                var frag_items: std.ArrayList(JSValue) = .empty;
                defer frag_items.deinit(vm.allocator);
                try getArrayElements(vm, f_arr, &frag_items);
                for (frag_items.items) |f_child| {
                    if (f_child.toObject()) |fc_obj| {
                        try fc_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), this_val);
                    }
                    try items.append(vm.allocator, f_child);
                }
                const empty_frag = try createArray(vm, &[_]JSValue{});
                try child_obj.setProperty(vm.allocator, children_atom, JSValue.fromObject(empty_frag));
            }
        } else {
            try child_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), this_val);
            try items.append(vm.allocator, args[0]);
        }

        const new_arr = try createArray(vm, items.items);
        try inst.setProperty(vm.allocator, children_atom, JSValue.fromObject(new_arr));
        try updateElementTreeRelationships(vm, inst);
    }

    return args[0];
}

fn nativeElementRemoveChild(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.undefined_val;

    const target_obj = args[0].toObject().?;
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentElement"), JSValue.null_val);
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("previousSibling"), JSValue.null_val);
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("nextSibling"), JSValue.null_val);
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("previousElementSibling"), JSValue.null_val);
    try target_obj.setProperty(vm.allocator, try vm.atom_table.intern("nextElementSibling"), JSValue.null_val);

    const children_atom = try vm.atom_table.intern("_children");
    const children_arr = (inst.getProperty(children_atom) orelse JSValue.undefined_val).toObject();
    if (children_arr) |c_arr| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, c_arr, &items);

        var new_items: std.ArrayList(JSValue) = .empty;
        defer new_items.deinit(vm.allocator);

        for (items.items) |item| {
            if (item.toObject() != target_obj) {
                try new_items.append(vm.allocator, item);
            }
        }

        const new_arr = try createArray(vm, new_items.items);
        try inst.setProperty(vm.allocator, children_atom, JSValue.fromObject(new_arr));
        try updateElementTreeRelationships(vm, inst);
    }

    return args[0];
}

fn nativeClassListAdd(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.undefined_val;

    const token = vm.atom_table.get(args[0].toStringAtom());
    const tokens_atom = try vm.atom_table.intern("_tokens");
    var list: std.ArrayList(JSValue) = .empty;
    defer list.deinit(vm.allocator);

    if (inst.getProperty(tokens_atom)) |val| {
        if (val.toObject()) |arr| {
            try getArrayElements(vm, arr, &list);
        }
    }

    for (list.items) |item| {
        if (item.isString() and std.mem.eql(u8, vm.atom_table.get(item.toStringAtom()), token)) {
            return JSValue.undefined_val;
        }
    }

    try list.append(vm.allocator, args[0]);
    const new_arr = try createArray(vm, list.items);
    try inst.setProperty(vm.allocator, tokens_atom, JSValue.fromObject(new_arr));
    try syncClassListProperties(vm, inst, list.items);
    return JSValue.undefined_val;
}

fn nativeClassListContains(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.false_val;

    const token = vm.atom_table.get(args[0].toStringAtom());
    const tokens_atom = try vm.atom_table.intern("_tokens");
    if (inst.getProperty(tokens_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);

            for (list.items) |item| {
                if (item.isString() and std.mem.eql(u8, vm.atom_table.get(item.toStringAtom()), token)) {
                    return JSValue.true_val;
                }
            }
        }
    }
    return JSValue.false_val;
}

fn nativeClassListRemove(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.undefined_val;

    const token = vm.atom_table.get(args[0].toStringAtom());
    const tokens_atom = try vm.atom_table.intern("_tokens");
    if (inst.getProperty(tokens_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);

            var new_list: std.ArrayList(JSValue) = .empty;
            defer new_list.deinit(vm.allocator);

            for (list.items) |item| {
                if (!item.isString() or !std.mem.eql(u8, vm.atom_table.get(item.toStringAtom()), token)) {
                    try new_list.append(vm.allocator, item);
                }
            }

            const new_arr = try createArray(vm, new_list.items);
            try inst.setProperty(vm.allocator, tokens_atom, JSValue.fromObject(new_arr));
            try syncClassListProperties(vm, inst, new_list.items);
        }
    }
    return JSValue.undefined_val;
}

fn nativeClassListToggle(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const has = try nativeClassListContains(ctx, this_val, args);
    if (has.toBoolean()) {
        _ = try nativeClassListRemove(ctx, this_val, args);
        return JSValue.false_val;
    } else {
        _ = try nativeClassListAdd(ctx, this_val, args);
        return JSValue.true_val;
    }
}

fn nativeDocumentCreateElement(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.undefined_val;

    const tag_str = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => "div",
    };

    const elem = try createJsElement(vm, tag_str);
    try elem.setProperty(vm.allocator, try vm.atom_table.intern("ownerDocument"), this_val);
    return JSValue.fromObject(elem);
}

fn nativeDocumentGetElementById(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.null_val;

    const target_id = switch (args[0].getType()) {
        .String => vm.atom_table.get(args[0].toStringAtom()),
        else => return JSValue.null_val,
    };

    const doc_obj = this_val.toObject() orelse return JSValue.null_val;
    const body_val = doc_obj.getProperty(try vm.atom_table.intern("body")) orelse return JSValue.null_val;
    const body_obj = body_val.toObject() orelse return JSValue.null_val;

    return findElementByIdRecursive(vm, body_obj, target_id);
}

fn findElementByIdRecursive(vm: *VM, elem: *JSObject, target_id: []const u8) anyerror!JSValue {
    if (elem.getProperty(try vm.atom_table.intern("id"))) |id_val| {
        if (id_val.isString()) {
            if (std.mem.eql(u8, vm.atom_table.get(id_val.toStringAtom()), target_id)) {
                return JSValue.fromObject(elem);
            }
        }
    }

    const children_atom = try vm.atom_table.intern("_children");
    if (elem.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    const found = try findElementByIdRecursive(vm, child, target_id);
                    if (!found.isNull()) return found;
                }
            }
        }
    }

    return JSValue.null_val;
}

const CombinatorInfo = struct {
    idx: usize,
    op: u8,
};

fn findLastSelectorCombinator(sel: []const u8) ?CombinatorInfo {
    var bracket_depth: usize = 0;
    var paren_depth: usize = 0;

    var i: usize = sel.len;
    while (i > 0) {
        i -= 1;
        const ch = sel[i];
        if (ch == ']') {
            bracket_depth += 1;
        } else if (ch == '[') {
            if (bracket_depth > 0) bracket_depth -= 1;
        } else if (ch == ')') {
            paren_depth += 1;
        } else if (ch == '(') {
            if (paren_depth > 0) paren_depth -= 1;
        } else if (bracket_depth == 0 and paren_depth == 0) {
            if (ch == '>') {
                return CombinatorInfo{ .idx = i, .op = '>' };
            } else if (ch == ' ') {
                const before = std.mem.trimEnd(u8, sel[0..i], " \t");
                const after = std.mem.trimStart(u8, sel[i + 1 ..], " \t");
                if (before.len > 0 and after.len > 0 and before[before.len - 1] != '>' and after[0] != '>') {
                    return CombinatorInfo{ .idx = i, .op = ' ' };
                }
            }
        }
    }
    return null;
}

fn jsElementGetAttributeString(vm: *VM, elem: *JSObject, name: []const u8) ?[]const u8 {
    const atom = vm.atom_table.intern(name) catch return null;
    if (elem.getProperty(atom)) |val| {
        if (val.isString()) {
            return vm.atom_table.get(val.toStringAtom());
        } else if (val.isBoolean()) {
            return if (val.toBoolean()) "" else null;
        }
    }
    return null;
}

fn jsElementHasAttribute(vm: *VM, elem: *JSObject, name: []const u8) bool {
    const atom = vm.atom_table.intern(name) catch return false;
    if (elem.getProperty(atom)) |val| {
        if (val.isBoolean()) return val.toBoolean();
        return !val.isNull() and !val.isUndefined();
    }
    return false;
}

fn elementMatchesSelector(vm: *VM, elem: *JSObject, sel_str: []const u8) bool {
    const trimmed = std.mem.trim(u8, sel_str, " \t\r\n");
    if (trimmed.len == 0) return false;

    // 1. Check for top-level comma outside brackets and parens
    var bracket_depth: usize = 0;
    var paren_depth: usize = 0;
    var last_start: usize = 0;
    var has_top_level_comma = false;
    for (trimmed, 0..) |ch, idx| {
        if (ch == '[') {
            bracket_depth += 1;
        } else if (ch == ']') {
            if (bracket_depth > 0) bracket_depth -= 1;
        } else if (ch == '(') {
            paren_depth += 1;
        } else if (ch == ')' and paren_depth > 0) {
            paren_depth -= 1;
        } else if (ch == ',' and bracket_depth == 0 and paren_depth == 0) {
            has_top_level_comma = true;
            const part = std.mem.trim(u8, trimmed[last_start..idx], " \t\r\n");
            if (part.len > 0 and elementMatchesSelector(vm, elem, part)) return true;
            last_start = idx + 1;
        }
    }
    if (has_top_level_comma) {
        const part = std.mem.trim(u8, trimmed[last_start..], " \t\r\n");
        return part.len > 0 and elementMatchesSelector(vm, elem, part);
    }

    // 2. Check for combinators (> and space)
    if (findLastSelectorCombinator(trimmed)) |comb| {
        const left = std.mem.trim(u8, trimmed[0..comb.idx], " \t\r\n");
        const right = std.mem.trim(u8, trimmed[comb.idx + 1 ..], " \t\r\n");
        if (left.len > 0 and right.len > 0) {
            if (!elementMatchesCompound(vm, elem, right)) return false;
            const parent_val = elem.getProperty(vm.atom_table.intern("parentNode") catch return false) orelse JSValue.null_val;
            if (parent_val.toObject()) |p_obj| {
                const nt = p_obj.getProperty(vm.atom_table.intern("nodeType") catch return false) orelse JSValue.fromInt32(0);
                if (comb.op == '>') {
                    return (nt.toInt32() == 1) and elementMatchesSelector(vm, p_obj, left);
                } else if (comb.op == ' ') {
                    var curr: ?*JSObject = p_obj;
                    while (curr) |par| {
                        const par_nt = par.getProperty(vm.atom_table.intern("nodeType") catch return false) orelse JSValue.fromInt32(0);
                        if (par_nt.toInt32() == 1 and elementMatchesSelector(vm, par, left)) return true;
                        const next_p = par.getProperty(vm.atom_table.intern("parentNode") catch return false) orelse JSValue.null_val;
                        curr = next_p.toObject();
                    }
                    return false;
                }
            }
            return false;
        }
    }

    // 3. Single compound selector
    return elementMatchesCompound(vm, elem, trimmed);
}

fn elementMatchesCompound(vm: *VM, elem: *JSObject, trimmed: []const u8) bool {
    if (trimmed.len == 0) return false;

    var i: usize = 0;
    // 1. Tag name (if any)
    if (trimmed[0] != '#' and trimmed[0] != '.' and trimmed[0] != '[' and trimmed[0] != ':') {
        const tag_end = std.mem.indexOfAny(u8, trimmed, "#.[:") orelse trimmed.len;
        const tag_part = trimmed[0..tag_end];
        if (!std.mem.eql(u8, tag_part, "*")) {
            const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse return false;
            if (tag_val.isString()) {
                const actual_tag = vm.atom_table.get(tag_val.toStringAtom());
                if (!std.ascii.eqlIgnoreCase(actual_tag, tag_part)) return false;
            } else {
                return false;
            }
        }
        i = tag_end;
    }

    // 2. Modifiers: #id, .class, [attr], :pseudo
    while (i < trimmed.len) {
        const ch = trimmed[i];
        if (ch == '#') {
            i += 1;
            const id_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
            const id_val = trimmed[i .. i + id_end];
            i += id_end;
            const id_prop = elem.getProperty(vm.atom_table.intern("id") catch return false) orelse return false;
            if (id_prop.isString()) {
                const actual_id = vm.atom_table.get(id_prop.toStringAtom());
                if (!std.mem.eql(u8, actual_id, id_val)) return false;
            } else {
                return false;
            }
        } else if (ch == '.') {
            i += 1;
            const class_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
            const class_val = trimmed[i .. i + class_end];
            i += class_end;

            var found = false;
            if (elem.getProperty(vm.atom_table.intern("classList") catch return false)) |cl_val| {
                const has = nativeClassListContains(@ptrCast(vm), cl_val, &[_]JSValue{
                    JSValue.fromStringAtom(vm.atom_table.intern(class_val) catch return false),
                }) catch JSValue.false_val;
                if (has.toBoolean()) found = true;
            }
            if (!found) {
                if (elem.getProperty(vm.atom_table.intern("className") catch return false)) |cn_val| {
                    if (cn_val.isString()) {
                        const cn_str = vm.atom_table.get(cn_val.toStringAtom());
                        var it = std.mem.tokenizeScalar(u8, cn_str, ' ');
                        while (it.next()) |tok| {
                            if (std.mem.eql(u8, tok, class_val)) {
                                found = true;
                                break;
                            }
                        }
                    }
                }
            }
            if (!found) return false;
        } else if (ch == '[') {
            const close_b = std.mem.indexOfScalar(u8, trimmed[i..], ']') orelse return false;
            const attr_expr = trimmed[i + 1 .. i + close_b];
            i += close_b + 1;

            if (std.mem.indexOf(u8, attr_expr, "^=")) |p_idx| {
                const attr_name = std.mem.trim(u8, attr_expr[0..p_idx], " \t'\"\\");
                const target_val = std.mem.trim(u8, attr_expr[p_idx + 2 ..], " \t'\"\\");
                const actual_val = jsElementGetAttributeString(vm, elem, attr_name) orelse return false;
                if (!std.mem.startsWith(u8, actual_val, target_val)) return false;
            } else if (std.mem.indexOf(u8, attr_expr, "$=")) |s_idx| {
                const attr_name = std.mem.trim(u8, attr_expr[0..s_idx], " \t'\"\\");
                const target_val = std.mem.trim(u8, attr_expr[s_idx + 2 ..], " \t'\"\\");
                const actual_val = jsElementGetAttributeString(vm, elem, attr_name) orelse return false;
                if (!std.mem.endsWith(u8, actual_val, target_val)) return false;
            } else if (std.mem.indexOf(u8, attr_expr, "*=")) |c_idx| {
                const attr_name = std.mem.trim(u8, attr_expr[0..c_idx], " \t'\"\\");
                const target_val = std.mem.trim(u8, attr_expr[c_idx + 2 ..], " \t'\"\\");
                const actual_val = jsElementGetAttributeString(vm, elem, attr_name) orelse return false;
                if (std.mem.indexOf(u8, actual_val, target_val) == null) return false;
            } else if (std.mem.indexOf(u8, attr_expr, "~=")) |w_idx| {
                const attr_name = std.mem.trim(u8, attr_expr[0..w_idx], " \t'\"\\");
                const target_val = std.mem.trim(u8, attr_expr[w_idx + 2 ..], " \t'\"\\");
                const actual_val = jsElementGetAttributeString(vm, elem, attr_name) orelse return false;
                var found = false;
                var it = std.mem.tokenizeScalar(u8, actual_val, ' ');
                while (it.next()) |tok| {
                    if (std.mem.eql(u8, tok, target_val)) { found = true; break; }
                }
                if (!found) return false;
            } else if (std.mem.indexOfScalar(u8, attr_expr, '=')) |eq_idx| {
                const attr_name = std.mem.trim(u8, attr_expr[0..eq_idx], " \t'\"\\");
                const target_val = std.mem.trim(u8, attr_expr[eq_idx + 1 ..], " \t'\"\\");
                const actual_val = jsElementGetAttributeString(vm, elem, attr_name) orelse return false;
                if (!std.mem.eql(u8, actual_val, target_val)) return false;
            } else {
                const attr_name = std.mem.trim(u8, attr_expr, " \t'\"\\");
                if (!jsElementHasAttribute(vm, elem, attr_name)) return false;
            }
        } else if (ch == ':') {
            i += 1;
            if (std.mem.startsWith(u8, trimmed[i..], "not(")) {
                i += 4;
                const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                const inner_sel = trimmed[i .. i + close_p];
                i += close_p + 1;
                if (elementMatchesSelector(vm, elem, inner_sel)) return false;
            } else if (std.mem.startsWith(u8, trimmed[i..], "nth-child(")) {
                i += 10;
                const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                i += close_p + 1;
                var idx: i32 = 1;
                var curr = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                while (!curr.isNull() and !curr.isUndefined()) {
                    if (curr.toObject()) |co| {
                        idx += 1;
                        curr = co.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    } else break;
                }
                if (!Node.evaluateNthExpression(idx, expr)) return false;
            } else if (std.mem.startsWith(u8, trimmed[i..], "nth-last-child(")) {
                i += 15;
                const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                i += close_p + 1;
                var idx: i32 = 1;
                var curr = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                while (!curr.isNull() and !curr.isUndefined()) {
                    if (curr.toObject()) |co| {
                        idx += 1;
                        curr = co.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    } else break;
                }
                if (!Node.evaluateNthExpression(idx, expr)) return false;
            } else if (std.mem.startsWith(u8, trimmed[i..], "nth-of-type(")) {
                i += 12;
                const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                i += close_p + 1;
                const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                const my_tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "";
                var idx: i32 = 1;
                var curr = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                while (!curr.isNull() and !curr.isUndefined()) {
                    if (curr.toObject()) |co| {
                        const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                        if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                            idx += 1;
                        }
                        curr = co.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    } else break;
                }
                if (!Node.evaluateNthExpression(idx, expr)) return false;
            } else if (std.mem.startsWith(u8, trimmed[i..], "nth-last-of-type(")) {
                i += 17;
                const close_p = std.mem.indexOfScalar(u8, trimmed[i..], ')') orelse return false;
                const expr = std.mem.trim(u8, trimmed[i .. i + close_p], " \t");
                i += close_p + 1;
                const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                const my_tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "";
                var idx: i32 = 1;
                var curr = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                while (!curr.isNull() and !curr.isUndefined()) {
                    if (curr.toObject()) |co| {
                        const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                        if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                            idx += 1;
                        }
                        curr = co.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    } else break;
                }
                if (!Node.evaluateNthExpression(idx, expr)) return false;
            } else {
                const pseudo_end = std.mem.indexOfAny(u8, trimmed[i..], ".#[:") orelse (trimmed.len - i);
                const pseudo = trimmed[i .. i + pseudo_end];
                i += pseudo_end;

                if (std.mem.eql(u8, pseudo, "first-child")) {
                    const prev = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    if (!prev.isNull() and !prev.isUndefined()) return false;
                } else if (std.mem.eql(u8, pseudo, "last-child")) {
                    const next = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    if (!next.isNull() and !next.isUndefined()) return false;
                } else if (std.mem.eql(u8, pseudo, "only-child")) {
                    const prev = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    if (!prev.isNull() and !prev.isUndefined()) return false;
                    const next = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    if (!next.isNull() and !next.isUndefined()) return false;
                } else if (std.mem.eql(u8, pseudo, "first-of-type")) {
                    const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                    const my_tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "";
                    var curr = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    while (!curr.isNull() and !curr.isUndefined()) {
                        if (curr.toObject()) |co| {
                            const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                            if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                                return false;
                            }
                            curr = co.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                        } else break;
                    }
                } else if (std.mem.eql(u8, pseudo, "last-of-type")) {
                    const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                    const my_tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "";
                    var curr = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    while (!curr.isNull() and !curr.isUndefined()) {
                        if (curr.toObject()) |co| {
                            const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                            if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                                return false;
                            }
                            curr = co.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                        } else break;
                    }
                } else if (std.mem.eql(u8, pseudo, "only-of-type")) {
                    const tag_val = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                    const my_tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "";
                    var curr = elem.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                    while (!curr.isNull() and !curr.isUndefined()) {
                        if (curr.toObject()) |co| {
                            const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                            if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                                return false;
                            }
                            curr = co.getProperty(vm.atom_table.intern("previousElementSibling") catch return false) orelse JSValue.null_val;
                        } else break;
                    }
                    var next_c = elem.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                    while (!next_c.isNull() and !next_c.isUndefined()) {
                        if (next_c.toObject()) |co| {
                            const s_tag_val = co.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                            if (s_tag_val.isString() and std.ascii.eqlIgnoreCase(vm.atom_table.get(s_tag_val.toStringAtom()), my_tag_str)) {
                                return false;
                            }
                            next_c = co.getProperty(vm.atom_table.intern("nextElementSibling") catch return false) orelse JSValue.null_val;
                        } else break;
                    }
                } else if (std.mem.eql(u8, pseudo, "empty")) {
                    const cnt = elem.getProperty(vm.atom_table.intern("childElementCount") catch return false) orelse JSValue.fromInt32(0);
                    if (cnt.toInt32() > 0) return false;
                    const tc = elem.getProperty(vm.atom_table.intern("textContent") catch return false) orelse JSValue.null_val;
                    if (tc.isString()) {
                        const tc_str = vm.atom_table.get(tc.toStringAtom());
                        if (std.mem.trim(u8, tc_str, " \t\r\n").len > 0) return false;
                    }
                } else if (std.mem.eql(u8, pseudo, "checked")) {
                    const has_chk = jsElementHasAttribute(vm, elem, "checked") or jsElementHasAttribute(vm, elem, "selected");
                    const chk_val = elem.getProperty(vm.atom_table.intern("checked") catch return false) orelse JSValue.false_val;
                    if (!has_chk and !chk_val.toBoolean()) return false;
                } else if (std.mem.eql(u8, pseudo, "disabled")) {
                    const has_dis = jsElementHasAttribute(vm, elem, "disabled");
                    const dis_val = elem.getProperty(vm.atom_table.intern("disabled") catch return false) orelse JSValue.false_val;
                    if (!has_dis and !dis_val.toBoolean()) return false;
                } else if (std.mem.eql(u8, pseudo, "enabled")) {
                    const has_dis = jsElementHasAttribute(vm, elem, "disabled");
                    const dis_val = elem.getProperty(vm.atom_table.intern("disabled") catch return false) orelse JSValue.false_val;
                    if (has_dis or dis_val.toBoolean()) return false;
                } else if (std.mem.eql(u8, pseudo, "root")) {
                    const parent = elem.getProperty(vm.atom_table.intern("parentNode") catch return false) orelse JSValue.null_val;
                    const tag = elem.getProperty(vm.atom_table.intern("tagName") catch return false) orelse JSValue.null_val;
                    if (!parent.isNull() and tag.isString()) {
                        const tag_str = vm.atom_table.get(tag.toStringAtom());
                        if (!std.ascii.eqlIgnoreCase(tag_str, "html")) return false;
                    }
                }
            }
        } else {
            break;
        }
    }
    return true;
}

fn findElementBySelectorRecursive(vm: *VM, elem: *JSObject, selector: []const u8) anyerror!JSValue {
    if (elementMatchesSelector(vm, elem, selector)) {
        return JSValue.fromObject(elem);
    }

    const children_atom = try vm.atom_table.intern("_children");
    if (elem.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    const found = try findElementBySelectorRecursive(vm, child, selector);
                    if (!found.isNull()) return found;
                }
            }
        }
    }
    return JSValue.null_val;
}

fn collectElementsBySelectorRecursive(vm: *VM, elem: *JSObject, selector: []const u8, results: *std.ArrayList(JSValue)) !void {
    if (elementMatchesSelector(vm, elem, selector)) {
        try results.append(vm.allocator, JSValue.fromObject(elem));
    }

    const children_atom = try vm.atom_table.intern("_children");
    if (elem.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    try collectElementsBySelectorRecursive(vm, child, selector, results);
                }
            }
        }
    }
}

fn nativeDocumentQuerySelector(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isString()) return JSValue.null_val;
    const sel = vm.atom_table.get(args[0].toStringAtom());

    const doc_obj = this_val.toObject() orelse return JSValue.null_val;
    const body_val = doc_obj.getProperty(try vm.atom_table.intern("body")) orelse return JSValue.null_val;
    const body_obj = body_val.toObject() orelse return JSValue.null_val;

    const children_atom = try vm.atom_table.intern("_children");
    if (body_obj.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    const found = try findElementBySelectorRecursive(vm, child, sel);
                    if (!found.isNull()) return found;
                }
            }
        }
    }

    return JSValue.null_val;
}

fn nativeDocumentQuerySelectorAll(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isString()) {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    }
    const sel = vm.atom_table.get(args[0].toStringAtom());

    const doc_obj = this_val.toObject() orelse {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    };
    const body_val = doc_obj.getProperty(try vm.atom_table.intern("body")) orelse {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    };
    const body_obj = body_val.toObject() orelse {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    };

    var results: std.ArrayList(JSValue) = .empty;
    defer results.deinit(vm.allocator);

    const children_atom = try vm.atom_table.intern("_children");
    if (body_obj.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    try collectElementsBySelectorRecursive(vm, child, sel, &results);
                }
            }
        }
    }

    const arr = try createArray(vm, results.items);
    return JSValue.fromObject(arr);
}

fn nativeDocumentCreateTextNode(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const text_str = if (args.len > 0 and args[0].isString())
        args[0]
    else
        JSValue.fromStringAtom(try vm.atom_table.intern(""));

    const text_node = try vm.gc.allocateObject(null);
    try text_node.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(3));
    try text_node.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#text")));
    try text_node.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), text_str);
    try text_node.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), text_str);
    try text_node.setProperty(vm.allocator, try vm.atom_table.intern("ownerDocument"), this_val);
    return JSValue.fromObject(text_node);
}

fn nativeElementQuerySelector(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.null_val;
    const sel = vm.atom_table.get(args[0].toStringAtom());

    const children_atom = try vm.atom_table.intern("_children");
    if (inst.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    const found = try findElementBySelectorRecursive(vm, child, sel);
                    if (!found.isNull()) return found;
                }
            }
        }
    }
    return JSValue.null_val;
}

fn nativeElementQuerySelectorAll(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    };
    if (args.len == 0 or !args[0].isString()) {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    }
    const sel = vm.atom_table.get(args[0].toStringAtom());

    var results: std.ArrayList(JSValue) = .empty;
    defer results.deinit(vm.allocator);

    const children_atom = try vm.atom_table.intern("_children");
    if (inst.getProperty(children_atom)) |c_val| {
        if (c_val.toObject()) |c_arr| {
            var items: std.ArrayList(JSValue) = .empty;
            defer items.deinit(vm.allocator);
            try getArrayElements(vm, c_arr, &items);

            for (items.items) |item| {
                if (item.toObject()) |child| {
                    try collectElementsBySelectorRecursive(vm, child, sel, &results);
                }
            }
        }
    }

    const arr = try createArray(vm, results.items);
    return JSValue.fromObject(arr);
}

fn nativeElementMatches(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.false_val;

    const sel = vm.atom_table.get(args[0].toStringAtom());
    const matched = elementMatchesSelector(vm, inst, sel);
    return if (matched) JSValue.true_val else JSValue.false_val;
}

fn nativeElementClosest(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    var curr: ?*JSObject = this_val.toObject();
    if (args.len == 0 or !args[0].isString()) return JSValue.null_val;

    const sel = vm.atom_table.get(args[0].toStringAtom());
    while (curr) |elem| {
        if (elementMatchesSelector(vm, elem, sel)) {
            return JSValue.fromObject(elem);
        }
        const parent_val = elem.getProperty(try vm.atom_table.intern("parentNode")) orelse JSValue.null_val;
        curr = parent_val.toObject();
    }
    return JSValue.null_val;
}

fn nativeElementHasAttribute(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const val = try nativeElementGetAttribute(ctx, this_val, args);
    return if (val.isNull()) JSValue.false_val else JSValue.true_val;
}

fn nativeElementRemoveAttribute(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.undefined_val;

    const attr_name = vm.atom_table.get(args[0].toStringAtom());
    const atom = vm.atom_table.map.get(attr_name) orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, atom, JSValue.null_val);

    const attrs_atom = try vm.atom_table.intern("_attrs");
    if (inst.getProperty(attrs_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            var new_list: std.ArrayList(JSValue) = .empty;
            defer new_list.deinit(vm.allocator);
            for (list.items) |it| {
                if (!it.isString() or !std.mem.eql(u8, vm.atom_table.get(it.toStringAtom()), attr_name)) {
                    try new_list.append(vm.allocator, it);
                }
            }
            const new_arr = try createArray(vm, new_list.items);
            try inst.setProperty(vm.allocator, attrs_atom, JSValue.fromObject(new_arr));
        }
    }

    if (std.mem.eql(u8, attr_name, "checked")) {
        try inst.setProperty(vm.allocator, atom, JSValue.false_val);
    } else if (std.mem.eql(u8, attr_name, "disabled")) {
        try inst.setProperty(vm.allocator, atom, JSValue.false_val);
    } else if (std.mem.eql(u8, attr_name, "class")) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("className"), JSValue.fromStringAtom(try vm.atom_table.intern("")));
        if (inst.getProperty(try vm.atom_table.intern("classList"))) |cl_val| {
            if (cl_val.toObject()) |cl_obj| {
                const empty_arr = try createArray(vm, &[_]JSValue{});
                try cl_obj.setProperty(vm.allocator, try vm.atom_table.intern("_tokens"), JSValue.fromObject(empty_arr));
                try syncClassListProperties(vm, cl_obj, &[_]JSValue{});
            }
        }
    }
    return JSValue.undefined_val;
}

fn nativeElementInsertBefore(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.undefined_val;

    const new_child = args[0];
    const new_obj = new_child.toObject().?;

    const children_atom = try vm.atom_table.intern("_children");
    const c_val = inst.getProperty(children_atom) orelse return args[0];
    const c_arr = c_val.toObject() orelse return args[0];

    var list: std.ArrayList(JSValue) = .empty;
    defer list.deinit(vm.allocator);
    try getArrayElements(vm, c_arr, &list);

    const nt_atom = try vm.atom_table.intern("nodeType");
    const is_frag = if (new_obj.getProperty(nt_atom)) |nt| nt.toInt32() == 11 else false;

    var insert_idx = list.items.len;
    if (args.len > 1 and args[1].isObject()) {
        const ref_obj = args[1].toObject().?;
        for (list.items, 0..) |it, idx| {
            if (it.toObject() == ref_obj) {
                insert_idx = idx;
                break;
            }
        }
    }

    if (is_frag) {
        const frag_children_arr = (new_obj.getProperty(children_atom) orelse JSValue.undefined_val).toObject();
        if (frag_children_arr) |f_arr| {
            var frag_items: std.ArrayList(JSValue) = .empty;
            defer frag_items.deinit(vm.allocator);
            try getArrayElements(vm, f_arr, &frag_items);
            for (frag_items.items, 0..) |f_child, fi| {
                if (f_child.toObject()) |fc_obj| {
                    try fc_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), this_val);
                }
                try list.insert(vm.allocator, insert_idx + fi, f_child);
            }
            const empty_frag = try createArray(vm, &[_]JSValue{});
            try new_obj.setProperty(vm.allocator, children_atom, JSValue.fromObject(empty_frag));
        }
    } else {
        try new_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), this_val);
        if (insert_idx < list.items.len) {
            try list.insert(vm.allocator, insert_idx, new_child);
        } else {
            try list.append(vm.allocator, new_child);
        }
    }

    const new_arr = try createArray(vm, list.items);
    try inst.setProperty(vm.allocator, children_atom, JSValue.fromObject(new_arr));
    try updateElementTreeRelationships(vm, inst);
    return new_child;
}

fn nativeElementClick(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const click_ev = try nativeEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try vm.atom_table.intern("click")),
    });
    return try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{click_ev});
}

fn nativeElementRemove(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const parent_val = inst.getProperty(try vm.atom_table.intern("parentNode")) orelse JSValue.null_val;
    if (parent_val.toObject()) |_| {
        return try nativeElementRemoveChild(ctx, parent_val, &[_]JSValue{this_val});
    }
    return JSValue.undefined_val;
}

fn nativeElementContains(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.false_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.false_val;
    const target = args[0].toObject().?;
    if (inst == target) return JSValue.true_val;

    const children_atom = try vm.atom_table.intern("_children");
    const ch_val = inst.getProperty(children_atom) orelse return JSValue.false_val;
    if (ch_val.toObject()) |arr_obj| {
        var children_items: std.ArrayList(JSValue) = .empty;
        defer children_items.deinit(vm.allocator);
        try getArrayElements(vm, arr_obj, &children_items);
        for (children_items.items) |child_val| {
            const res = try nativeElementContains(ctx, child_val, args);
            if (res.toBoolean()) return JSValue.true_val;
        }
    }
    return JSValue.false_val;
}

fn nativeElementCloneNode(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    const nt_val = inst.getProperty(try vm.atom_table.intern("nodeType")) orelse JSValue.fromInt32(1);

    if (nt_val.toInt32() == 3) {
        const text_val = inst.getProperty(try vm.atom_table.intern("textContent")) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
        const text_obj = try vm.gc.allocateObject(null);
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(3));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#text")));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), text_val);
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), text_val);
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
        return JSValue.fromObject(text_obj);
    }

    if (nt_val.toInt32() == 8) {
        const data_val = inst.getProperty(try vm.atom_table.intern("data")) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
        const comment_obj = try vm.gc.allocateObject(null);
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(8));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#comment")));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("data"), data_val);
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), data_val);
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), data_val);
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
        return JSValue.fromObject(comment_obj);
    }

    const tag_atom = try vm.atom_table.intern("tagName");
    const tag_val = inst.getProperty(tag_atom) orelse JSValue.fromStringAtom(try vm.atom_table.intern("div"));
    const tag_str = if (tag_val.isString()) vm.atom_table.get(tag_val.toStringAtom()) else "div";
    const clone = try createJsElement(vm, tag_str);

    if (inst.getProperty(try vm.atom_table.intern("id"))) |id_val| {
        try clone.setProperty(vm.allocator, try vm.atom_table.intern("id"), id_val);
    }
    if (inst.getProperty(try vm.atom_table.intern("className"))) |cn_val| {
        try clone.setProperty(vm.allocator, try vm.atom_table.intern("className"), cn_val);
    }

    const attrs_atom = try vm.atom_table.intern("_attrs");
    if (inst.getProperty(attrs_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);
            for (list.items) |attr_name_val| {
                if (attr_name_val.isString()) {
                    if (inst.getProperty(attr_name_val.toStringAtom())) |av| {
                        _ = try nativeElementSetAttribute(ctx, JSValue.fromObject(clone), &[_]JSValue{
                            attr_name_val,
                            av,
                        });
                    }
                }
            }
        }
    }

    const deep = args.len > 0 and args[0].toBoolean();
    if (deep) {
        const children_atom = try vm.atom_table.intern("_children");
        if (inst.getProperty(children_atom)) |ch_val| {
            if (ch_val.toObject()) |arr_obj| {
                var items: std.ArrayList(JSValue) = .empty;
                defer items.deinit(vm.allocator);
                try getArrayElements(vm, arr_obj, &items);
                for (items.items) |child_val| {
                    const cloned_child = try nativeElementCloneNode(ctx, child_val, &[_]JSValue{JSValue.true_val});
                    _ = try nativeElementAppendChild(ctx, JSValue.fromObject(clone), &[_]JSValue{cloned_child});
                }
            }
        }
    }
    return JSValue.fromObject(clone);
}

fn nativeElementReplaceChild(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len < 2 or !args[0].isObject() or !args[1].isObject()) return JSValue.undefined_val;
    const new_child = args[0];
    const old_child = args[1];

    _ = try nativeElementInsertBefore(ctx, this_val, &[_]JSValue{ new_child, old_child });
    _ = try nativeElementRemoveChild(ctx, this_val, &[_]JSValue{old_child});
    return old_child;
}

fn collectElementsByTagName(vm: *VM, elem_obj: *JSObject, match_tag: []const u8, out: *std.ArrayList(JSValue)) anyerror!void {
    const children_atom = try vm.atom_table.intern("_children");
    const ch_val = elem_obj.getProperty(children_atom) orelse return;
    if (ch_val.toObject()) |arr_obj| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, arr_obj, &items);
        for (items.items) |child_val| {
            if (child_val.toObject()) |child_obj| {
                const tag_atom = try vm.atom_table.intern("tagName");
                if (child_obj.getProperty(tag_atom)) |tv| {
                    if (tv.isString()) {
                        const s = vm.atom_table.get(tv.toStringAtom());
                        if (std.mem.eql(u8, match_tag, "*") or std.ascii.eqlIgnoreCase(s, match_tag)) {
                            try out.append(vm.allocator, child_val);
                        }
                    }
                }
                try collectElementsByTagName(vm, child_obj, match_tag, out);
            }
        }
    }
}

fn nativeElementGetElementsByTagName(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    }
    const match_tag = vm.atom_table.get(args[0].toStringAtom());
    var out: std.ArrayList(JSValue) = .empty;
    defer out.deinit(vm.allocator);
    try collectElementsByTagName(vm, inst, match_tag, &out);
    const arr = try createArray(vm, out.items);
    return JSValue.fromObject(arr);
}

fn collectElementsByClassName(vm: *VM, elem_obj: *JSObject, match_class: []const u8, out: *std.ArrayList(JSValue)) anyerror!void {
    const children_atom = try vm.atom_table.intern("_children");
    const ch_val = elem_obj.getProperty(children_atom) orelse return;
    if (ch_val.toObject()) |arr_obj| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, arr_obj, &items);
        for (items.items) |child_val| {
            if (child_val.toObject()) |child_obj| {
                const cn_atom = try vm.atom_table.intern("className");
                if (child_obj.getProperty(cn_atom)) |cv| {
                    if (cv.isString()) {
                        const s = vm.atom_table.get(cv.toStringAtom());
                        var it = std.mem.tokenizeScalar(u8, s, ' ');
                        var matched = false;
                        while (it.next()) |cls| {
                            if (std.mem.eql(u8, cls, match_class)) {
                                matched = true;
                                break;
                            }
                        }
                        if (matched) {
                            try out.append(vm.allocator, child_val);
                        }
                    }
                }
                try collectElementsByClassName(vm, child_obj, match_class, out);
            }
        }
    }
}

fn nativeElementGetElementsByClassName(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    }
    const match_class = vm.atom_table.get(args[0].toStringAtom());
    var out: std.ArrayList(JSValue) = .empty;
    defer out.deinit(vm.allocator);
    try collectElementsByClassName(vm, inst, match_class, &out);
    const arr = try createArray(vm, out.items);
    return JSValue.fromObject(arr);
}

fn nativeDocumentGetElementsByTagName(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const doc_obj = this_val.toObject() orelse return JSValue.undefined_val;
    const body_atom = try vm.atom_table.intern("body");
    const body_val = doc_obj.getProperty(body_atom) orelse return JSValue.undefined_val;
    return nativeElementGetElementsByTagName(ctx, body_val, args);
}

fn nativeDocumentGetElementsByClassName(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const doc_obj = this_val.toObject() orelse return JSValue.undefined_val;
    const body_atom = try vm.atom_table.intern("body");
    const body_val = doc_obj.getProperty(body_atom) orelse return JSValue.undefined_val;
    return nativeElementGetElementsByClassName(ctx, body_val, args);
}

fn nativeElementGetBoundingClientRect(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const rect = try vm.gc.allocateObject(null);
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("x"), JSValue.fromFloat64(0.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("y"), JSValue.fromFloat64(0.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("width"), JSValue.fromFloat64(100.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("height"), JSValue.fromFloat64(100.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("top"), JSValue.fromFloat64(0.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("right"), JSValue.fromFloat64(100.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("bottom"), JSValue.fromFloat64(100.0));
    try rect.setProperty(vm.allocator, try vm.atom_table.intern("left"), JSValue.fromFloat64(0.0));
    return JSValue.fromObject(rect);
}

fn nativeElementGetClientRects(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const rect = try nativeElementGetBoundingClientRect(ctx, this_val, args);
    const arr = try createArray(vm, &[_]JSValue{rect});
    return JSValue.fromObject(arr);
}

fn nativeGetComputedStyle(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const cs = try createCSSStyleDeclaration(vm);
    const target = if (args.len > 0 and args[0].isObject()) args[0].toObject().? else null;

    if (target) |tgt| {
        if (tgt.getProperty(try vm.atom_table.intern("style"))) |style_val| {
            if (style_val.toObject()) |style_obj| {
                var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
                defer entries.deinit(vm.allocator);
                try style_obj.getPropertyEntries(vm.allocator, &entries);
                for (entries.items) |entry| {
                    try cs.setProperty(vm.allocator, entry.atom, entry.value);
                }
            }
        }
    }

    const def_display = cs.getProperty(try vm.atom_table.intern("display")) orelse JSValue.fromStringAtom(try vm.atom_table.intern("block"));
    try cs.setProperty(vm.allocator, try vm.atom_table.intern("display"), def_display);
    const def_visibility = cs.getProperty(try vm.atom_table.intern("visibility")) orelse JSValue.fromStringAtom(try vm.atom_table.intern("visible"));
    try cs.setProperty(vm.allocator, try vm.atom_table.intern("visibility"), def_visibility);
    const def_opacity = cs.getProperty(try vm.atom_table.intern("opacity")) orelse JSValue.fromStringAtom(try vm.atom_table.intern("1"));
    try cs.setProperty(vm.allocator, try vm.atom_table.intern("opacity"), def_opacity);

    return JSValue.fromObject(cs);
}

fn nativeMatchMedia(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const mql = try vm.gc.allocateObject(null);
    var media_str: []const u8 = "";
    if (args.len > 0 and args[0].isString()) {
        media_str = vm.atom_table.get(args[0].toStringAtom());
    }
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("media"), JSValue.fromStringAtom(try vm.atom_table.intern(media_str)));
    var matches = true;
    if (std.mem.indexOf(u8, media_str, "not all") != null) matches = false;
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("matches"), if (matches) JSValue.true_val else JSValue.false_val);

    const add_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetAddEventListener, @ptrCast(vm));
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("addEventListener"), JSValue.fromObject(add_ev_fn));
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("addListener"), JSValue.fromObject(add_ev_fn));
    const rem_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetRemoveEventListener, @ptrCast(vm));
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("removeEventListener"), JSValue.fromObject(rem_ev_fn));
    try mql.setProperty(vm.allocator, try vm.atom_table.intern("removeListener"), JSValue.fromObject(rem_ev_fn));

    return JSValue.fromObject(mql);
}

fn nativeWindowScrollTo(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeWindowAlert(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeWindowConfirm(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.true_val;
}

fn nativeWindowPrompt(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len > 1 and args[1].isString()) return args[1];
    return JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeMutationObserverConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const obs = try vm.gc.allocateObject(null);
    if (args.len > 0) {
        try obs.setProperty(vm.allocator, try vm.atom_table.intern("_cb"), args[0]);
    }
    const observe_fn = try vm.gc.allocateFunction(null, nativeObserverNoop, @ptrCast(vm));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("observe"), JSValue.fromObject(observe_fn));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("disconnect"), JSValue.fromObject(observe_fn));
    const take_fn = try vm.gc.allocateFunction(null, nativeObserverTakeRecords, @ptrCast(vm));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("takeRecords"), JSValue.fromObject(take_fn));
    return JSValue.fromObject(obs);
}

fn nativeResizeObserverConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const obs = try vm.gc.allocateObject(null);
    if (args.len > 0) {
        try obs.setProperty(vm.allocator, try vm.atom_table.intern("_cb"), args[0]);
    }
    const observe_fn = try vm.gc.allocateFunction(null, nativeObserverNoop, @ptrCast(vm));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("observe"), JSValue.fromObject(observe_fn));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("unobserve"), JSValue.fromObject(observe_fn));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("disconnect"), JSValue.fromObject(observe_fn));
    return JSValue.fromObject(obs);
}

fn nativeIntersectionObserverConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const obs = try vm.gc.allocateObject(null);
    if (args.len > 0) {
        try obs.setProperty(vm.allocator, try vm.atom_table.intern("_cb"), args[0]);
    }
    const observe_fn = try vm.gc.allocateFunction(null, nativeObserverNoop, @ptrCast(vm));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("observe"), JSValue.fromObject(observe_fn));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("unobserve"), JSValue.fromObject(observe_fn));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("disconnect"), JSValue.fromObject(observe_fn));
    const take_fn = try vm.gc.allocateFunction(null, nativeObserverTakeRecords, @ptrCast(vm));
    try obs.setProperty(vm.allocator, try vm.atom_table.intern("takeRecords"), JSValue.fromObject(take_fn));
    return JSValue.fromObject(obs);
}

fn nativeObserverNoop(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeObserverTakeRecords(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const empty_arr = try createArray(vm, &[_]JSValue{});
    return JSValue.fromObject(empty_arr);
}

fn nativeDateTimeFormatConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const dtf = try vm.gc.allocateObject(null);
    const fmt_fn = try vm.gc.allocateFunction(null, nativeDateTimeFormatFormat, @ptrCast(vm));
    try dtf.setProperty(vm.allocator, try vm.atom_table.intern("format"), JSValue.fromObject(fmt_fn));
    return JSValue.fromObject(dtf);
}

fn nativeDateTimeFormatFormat(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return JSValue.fromStringAtom(try vm.atom_table.intern("1/1/2026, 12:00:00 AM"));
}

fn nativeNumberFormatConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const nf = try vm.gc.allocateObject(null);
    const fmt_fn = try vm.gc.allocateFunction(null, nativeNumberFormatFormat, @ptrCast(vm));
    try nf.setProperty(vm.allocator, try vm.atom_table.intern("format"), JSValue.fromObject(fmt_fn));
    return JSValue.fromObject(nf);
}

fn nativeNumberFormatFormat(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0) return JSValue.fromStringAtom(try vm.atom_table.intern("0"));
    var buf: [64]u8 = undefined;
    const str = switch (args[0].getType()) {
        .Int32 => std.fmt.bufPrint(&buf, "{d}", .{args[0].toInt32()}) catch "0",
        .Float64 => std.fmt.bufPrint(&buf, "{d}", .{args[0].toFloat64()}) catch "0",
        else => "0",
    };
    return JSValue.fromStringAtom(try vm.atom_table.intern(str));
}

fn nativeElementIsSameNode(_: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0 or !args[0].isObject()) return JSValue.false_val;
    return JSValue.fromBoolean(this_val.toObject() == args[0].toObject());
}

fn nativeElementIsEqualNode(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isObject()) return JSValue.false_val;
    const a = this_val.toObject() orelse return JSValue.false_val;
    const b = args[0].toObject().?;
    if (a == b) return JSValue.true_val;

    const nt_atom = try vm.atom_table.intern("nodeType");
    const a_nt = a.getProperty(nt_atom) orelse JSValue.undefined_val;
    const b_nt = b.getProperty(nt_atom) orelse JSValue.undefined_val;
    if (a_nt.toInt32() != b_nt.toInt32()) return JSValue.false_val;

    const nn_atom = try vm.atom_table.intern("nodeName");
    const a_nn = a.getProperty(nn_atom) orelse JSValue.undefined_val;
    const b_nn = b.getProperty(nn_atom) orelse JSValue.undefined_val;
    if (a_nn.isString() and b_nn.isString()) {
        if (!std.mem.eql(u8, vm.atom_table.get(a_nn.toStringAtom()), vm.atom_table.get(b_nn.toStringAtom()))) {
            return JSValue.false_val;
        }
    }

    const id_atom = try vm.atom_table.intern("id");
    const a_id = a.getProperty(id_atom) orelse JSValue.undefined_val;
    const b_id = b.getProperty(id_atom) orelse JSValue.undefined_val;
    if (a_id.isString() and b_id.isString()) {
        if (!std.mem.eql(u8, vm.atom_table.get(a_id.toStringAtom()), vm.atom_table.get(b_id.toStringAtom()))) {
            return JSValue.false_val;
        }
    }

    const cls_atom = try vm.atom_table.intern("className");
    const a_cls = a.getProperty(cls_atom) orelse JSValue.undefined_val;
    const b_cls = b.getProperty(cls_atom) orelse JSValue.undefined_val;
    if (a_cls.isString() and b_cls.isString()) {
        if (!std.mem.eql(u8, vm.atom_table.get(a_cls.toStringAtom()), vm.atom_table.get(b_cls.toStringAtom()))) {
            return JSValue.false_val;
        }
    }

    return JSValue.true_val;
}

fn nativeElementCompareDocumentPosition(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0 or !args[0].isObject()) return JSValue.fromInt32(1); // DISCONNECTED
    const this_obj = this_val.toObject() orelse return JSValue.fromInt32(1);
    const other_obj = args[0].toObject().?;
    if (this_obj == other_obj) return JSValue.fromInt32(0);

    const contains_res = try nativeElementContains(ctx, this_val, args);
    if (contains_res.toBoolean()) {
        return JSValue.fromInt32(16 | 4); // CONTAINED_BY | FOLLOWING
    }

    const rev_contains_res = try nativeElementContains(ctx, args[0], &[_]JSValue{this_val});
    if (rev_contains_res.toBoolean()) {
        return JSValue.fromInt32(8 | 2); // CONTAINS | PRECEDING
    }

    return JSValue.fromInt32(1); // DISCONNECTED
}

fn serializeJsElement(vm: *VM, obj: *JSObject, out: *std.ArrayList(u8)) anyerror!void {
    const node_type_val = obj.getProperty(try vm.atom_table.intern("nodeType")) orelse JSValue.fromInt32(1);
    const node_type = node_type_val.toInt32();

    if (node_type == 3) {
        if (obj.getProperty(try vm.atom_table.intern("textContent"))) |tc| {
            if (tc.isString()) {
                try out.appendSlice(vm.allocator, vm.atom_table.get(tc.toStringAtom()));
            }
        }
        return;
    }

    if (node_type == 8) {
        try out.appendSlice(vm.allocator, "<!--");
        if (obj.getProperty(try vm.atom_table.intern("data"))) |d| {
            if (d.isString()) {
                try out.appendSlice(vm.allocator, vm.atom_table.get(d.toStringAtom()));
            }
        }
        try out.appendSlice(vm.allocator, "-->");
        return;
    }

    if (node_type == 9) {
        if (obj.getProperty(try vm.atom_table.intern("body"))) |b| {
            if (b.toObject()) |b_obj| {
                try serializeJsElement(vm, b_obj, out);
            }
        }
        return;
    }

    if (node_type == 11) {
        const children_atom = try vm.atom_table.intern("_children");
        if (obj.getProperty(children_atom)) |c_val| {
            if (c_val.toObject()) |c_arr| {
                var items: std.ArrayList(JSValue) = .empty;
                defer items.deinit(vm.allocator);
                try getArrayElements(vm, c_arr, &items);
                for (items.items) |it| {
                    if (it.toObject()) |child_obj| {
                        try serializeJsElement(vm, child_obj, out);
                    }
                }
            }
        }
        return;
    }

    var tag_name: []const u8 = "div";
    if (obj.getProperty(try vm.atom_table.intern("tagName"))) |tn| {
        if (tn.isString()) {
            tag_name = vm.atom_table.get(tn.toStringAtom());
        }
    }

    try out.append(vm.allocator, '<');
    try out.appendSlice(vm.allocator, tag_name);

    if (obj.getProperty(try vm.atom_table.intern("id"))) |id_val| {
        if (id_val.isString()) {
            const id_str = vm.atom_table.get(id_val.toStringAtom());
            if (id_str.len > 0) {
                try out.appendSlice(vm.allocator, " id=\"");
                try out.appendSlice(vm.allocator, id_str);
                try out.append(vm.allocator, '"');
            }
        }
    }

    if (obj.getProperty(try vm.atom_table.intern("className"))) |cls_val| {
        if (cls_val.isString()) {
            const cls_str = vm.atom_table.get(cls_val.toStringAtom());
            if (cls_str.len > 0) {
                try out.appendSlice(vm.allocator, " class=\"");
                try out.appendSlice(vm.allocator, cls_str);
                try out.append(vm.allocator, '"');
            }
        }
    }

    try out.append(vm.allocator, '>');

    const is_void = std.ascii.eqlIgnoreCase(tag_name, "img") or
        std.ascii.eqlIgnoreCase(tag_name, "br") or
        std.ascii.eqlIgnoreCase(tag_name, "hr") or
        std.ascii.eqlIgnoreCase(tag_name, "input") or
        std.ascii.eqlIgnoreCase(tag_name, "meta") or
        std.ascii.eqlIgnoreCase(tag_name, "link");

    if (!is_void) {
        const children_atom = try vm.atom_table.intern("_children");
        if (obj.getProperty(children_atom)) |c_val| {
            if (c_val.toObject()) |c_arr| {
                var items: std.ArrayList(JSValue) = .empty;
                defer items.deinit(vm.allocator);
                try getArrayElements(vm, c_arr, &items);
                for (items.items) |it| {
                    if (it.toObject()) |child_obj| {
                        try serializeJsElement(vm, child_obj, out);
                    }
                }
            }
        }
        try out.appendSlice(vm.allocator, "</");
        try out.appendSlice(vm.allocator, tag_name);
        try out.append(vm.allocator, '>');
    }
}

fn nativeXMLSerializerConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const serialize_fn = try vm.gc.allocateFunction(null, nativeXMLSerializerSerializeToString, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("serializeToString"), JSValue.fromObject(serialize_fn));
    return JSValue.fromObject(inst);
}

fn nativeXMLSerializerSerializeToString(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isObject()) return JSValue.fromStringAtom(try vm.atom_table.intern(""));
    const node_obj = args[0].toObject().?;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    try serializeJsElement(vm, node_obj, &out);

    const atom = try vm.atom_table.intern(out.items);
    return JSValue.fromStringAtom(atom);
}

fn nodeToJsElement(vm: *VM, node: *const Node) anyerror!*JSObject {
    if (node.node_type == .Text) {
        const text_str = node.text_content orelse "";
        const text_atom = try vm.atom_table.intern(text_str);
        const text_obj = try vm.gc.allocateObject(null);
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(3));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#text")));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), JSValue.fromStringAtom(text_atom));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), JSValue.fromStringAtom(text_atom));
        try text_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
        return text_obj;
    }

    if (node.node_type == .Comment) {
        const text_str = node.text_content orelse "";
        const text_atom = try vm.atom_table.intern(text_str);
        const comment_obj = try vm.gc.allocateObject(null);
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(8));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#comment")));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("data"), JSValue.fromStringAtom(text_atom));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), JSValue.fromStringAtom(text_atom));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), JSValue.fromStringAtom(text_atom));
        try comment_obj.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
        return comment_obj;
    }

    const tag_str = vm.atom_table.get(node.tag_name);
    const elem = try createJsElement(vm, tag_str);

    for (node.attributes.items) |attr| {
        const attr_name = vm.atom_table.get(attr.name);
        const val_str = std.mem.trim(u8, attr.value, "\"\'");
        const val_atom = try vm.atom_table.intern(val_str);
        _ = try nativeElementSetAttribute(@ptrCast(vm), JSValue.fromObject(elem), &[_]JSValue{
            JSValue.fromStringAtom(attr.name),
            JSValue.fromStringAtom(val_atom),
        });
        if (std.mem.eql(u8, attr_name, "id")) {
            try elem.setProperty(vm.allocator, try vm.atom_table.intern("id"), JSValue.fromStringAtom(val_atom));
        } else if (std.mem.eql(u8, attr_name, "class")) {
            try elem.setProperty(vm.allocator, try vm.atom_table.intern("className"), JSValue.fromStringAtom(val_atom));
            var it = std.mem.tokenizeScalar(u8, val_str, ' ');
            while (it.next()) |cls| {
                const cls_atom = try vm.atom_table.intern(cls);
                const cl_val = elem.getProperty(try vm.atom_table.intern("classList")) orelse continue;
                _ = try nativeClassListAdd(@ptrCast(vm), cl_val, &[_]JSValue{JSValue.fromStringAtom(cls_atom)});
            }
        }
    }

    var curr = node.first_child;
    while (curr) |ch| : (curr = ch.next_sibling) {
        const child_obj = try nodeToJsElement(vm, ch);
        _ = try nativeElementAppendChild(@ptrCast(vm), JSValue.fromObject(elem), &[_]JSValue{JSValue.fromObject(child_obj)});
    }

    return elem;
}

fn collectElementsByName(vm: *VM, elem: *JSObject, match_name: []const u8, out: *std.ArrayList(JSValue)) anyerror!void {
    const children_atom = try vm.atom_table.intern("_children");
    const ch_val = elem.getProperty(children_atom) orelse return;
    if (ch_val.toObject()) |arr_obj| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, arr_obj, &items);
        for (items.items) |child_val| {
            if (child_val.toObject()) |child_obj| {
                const name_atom = try vm.atom_table.intern("name");
                if (child_obj.getProperty(name_atom)) |nv| {
                    if (nv.isString()) {
                        const s = vm.atom_table.get(nv.toStringAtom());
                        if (std.mem.eql(u8, s, match_name)) {
                            try out.append(vm.allocator, child_val);
                        }
                    }
                }
                try collectElementsByName(vm, child_obj, match_name, out);
            }
        }
    }
}

fn nativeDocumentGetElementsByName(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const doc_obj = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) {
        const empty_arr = try createArray(vm, &[_]JSValue{});
        return JSValue.fromObject(empty_arr);
    }
    const match_name = vm.atom_table.get(args[0].toStringAtom());
    var out: std.ArrayList(JSValue) = .empty;
    defer out.deinit(vm.allocator);

    const body_val = doc_obj.getProperty(try vm.atom_table.intern("body")) orelse return JSValue.undefined_val;
    if (body_val.toObject()) |body_obj| {
        try collectElementsByName(vm, body_obj, match_name, &out);
    }

    const arr = try createArray(vm, out.items);
    return JSValue.fromObject(arr);
}

fn nativeDocumentCreateComment(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const data_val = if (args.len > 0 and args[0].isString()) args[0] else JSValue.fromStringAtom(try vm.atom_table.intern(""));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(8));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#comment")));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("data"), data_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("textContent"), data_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("nodeValue"), data_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("ownerDocument"), this_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("parentNode"), JSValue.null_val);
    return JSValue.fromObject(inst);
}

fn nativeDocumentContains(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const doc_obj = this_val.toObject() orelse return JSValue.false_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.false_val;
    const target = args[0].toObject().?;
    if (doc_obj == target) return JSValue.true_val;

    if (doc_obj.getProperty(try vm.atom_table.intern("documentElement"))) |html_val| {
        if (html_val.toObject()) |html_obj| {
            if (html_obj == target) return JSValue.true_val;
            const res = try nativeElementContains(ctx, html_val, args);
            if (res.toBoolean()) return JSValue.true_val;
        }
    }
    if (doc_obj.getProperty(try vm.atom_table.intern("body"))) |body_val| {
        if (body_val.toObject()) |body_obj| {
            if (body_obj == target) return JSValue.true_val;
            const res = try nativeElementContains(ctx, body_val, args);
            if (res.toBoolean()) return JSValue.true_val;
        }
    }
    return JSValue.false_val;
}

pub fn createJsDocument(vm: *VM) anyerror!*JSObject {
    const alloc = vm.allocator;
    const table = vm.atom_table;
    const doc_obj = try vm.gc.allocateObject(null);
    const body_elem = try createJsElement(vm, "body");
    const head_elem = try createJsElement(vm, "head");
    const html_elem = try createJsElement(vm, "html");

    try doc_obj.setProperty(alloc, try table.intern("body"), JSValue.fromObject(body_elem));
    try doc_obj.setProperty(alloc, try table.intern("head"), JSValue.fromObject(head_elem));
    try doc_obj.setProperty(alloc, try table.intern("documentElement"), JSValue.fromObject(html_elem));
    try doc_obj.setProperty(alloc, try table.intern("title"), JSValue.fromStringAtom(try table.intern("Davoth Browser")));
    try doc_obj.setProperty(alloc, try table.intern("cookie"), JSValue.fromStringAtom(try table.intern("")));
    try doc_obj.setProperty(alloc, try table.intern("readyState"), JSValue.fromStringAtom(try table.intern("complete")));
    try doc_obj.setProperty(alloc, try table.intern("defaultView"), JSValue.fromObject(vm.global_object));
    try doc_obj.setProperty(alloc, try table.intern("nodeType"), JSValue.fromInt32(9));
    try doc_obj.setProperty(alloc, try table.intern("nodeName"), JSValue.fromStringAtom(try table.intern("#document")));
    try doc_obj.setProperty(alloc, try table.intern("compatMode"), JSValue.fromStringAtom(try table.intern("CSS1Compat")));
    try doc_obj.setProperty(alloc, try table.intern("characterSet"), JSValue.fromStringAtom(try table.intern("UTF-8")));
    try doc_obj.setProperty(alloc, try table.intern("contentType"), JSValue.fromStringAtom(try table.intern("text/html")));
    try doc_obj.setProperty(alloc, try table.intern("hidden"), JSValue.false_val);
    try doc_obj.setProperty(alloc, try table.intern("visibilityState"), JSValue.fromStringAtom(try table.intern("visible")));

    try body_elem.setProperty(alloc, try table.intern("ownerDocument"), JSValue.fromObject(doc_obj));
    try head_elem.setProperty(alloc, try table.intern("ownerDocument"), JSValue.fromObject(doc_obj));
    try html_elem.setProperty(alloc, try table.intern("ownerDocument"), JSValue.fromObject(doc_obj));

    const create_elem_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateElement, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createElement"), JSValue.fromObject(create_elem_fn));

    const get_elem_id_fn = try vm.gc.allocateFunction(null, nativeDocumentGetElementById, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("getElementById"), JSValue.fromObject(get_elem_id_fn));

    const doc_qs_fn = try vm.gc.allocateFunction(null, nativeDocumentQuerySelector, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("querySelector"), JSValue.fromObject(doc_qs_fn));

    const doc_qsa_fn = try vm.gc.allocateFunction(null, nativeDocumentQuerySelectorAll, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("querySelectorAll"), JSValue.fromObject(doc_qsa_fn));

    const doc_get_tag_fn = try vm.gc.allocateFunction(null, nativeDocumentGetElementsByTagName, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("getElementsByTagName"), JSValue.fromObject(doc_get_tag_fn));

    const doc_get_cls_fn = try vm.gc.allocateFunction(null, nativeDocumentGetElementsByClassName, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("getElementsByClassName"), JSValue.fromObject(doc_get_cls_fn));

    const doc_create_text_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateTextNode, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createTextNode"), JSValue.fromObject(doc_create_text_fn));

    const doc_create_frag_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateDocumentFragment, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createDocumentFragment"), JSValue.fromObject(doc_create_frag_fn));

    const doc_add_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetAddEventListener, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("addEventListener"), JSValue.fromObject(doc_add_ev_fn));

    const doc_rem_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetRemoveEventListener, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("removeEventListener"), JSValue.fromObject(doc_rem_ev_fn));

    const doc_disp_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetDispatchEvent, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("dispatchEvent"), JSValue.fromObject(doc_disp_ev_fn));

    const doc_create_range_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateRange, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createRange"), JSValue.fromObject(doc_create_range_fn));

    const doc_create_ev_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateEvent, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createEvent"), JSValue.fromObject(doc_create_ev_fn));

    const doc_get_sel_fn = try vm.gc.allocateFunction(null, nativeGetSelection, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("getSelection"), JSValue.fromObject(doc_get_sel_fn));

    const doc_get_name_fn = try vm.gc.allocateFunction(null, nativeDocumentGetElementsByName, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("getElementsByName"), JSValue.fromObject(doc_get_name_fn));

    const doc_create_comment_fn = try vm.gc.allocateFunction(null, nativeDocumentCreateComment, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("createComment"), JSValue.fromObject(doc_create_comment_fn));

    const doc_contains_fn = try vm.gc.allocateFunction(null, nativeDocumentContains, @ptrCast(vm));
    try doc_obj.setProperty(alloc, try table.intern("contains"), JSValue.fromObject(doc_contains_fn));

    // HTMLCollections and script reference
    const empty_forms = try createArray(vm, &[_]JSValue{});
    try doc_obj.setProperty(alloc, try table.intern("forms"), JSValue.fromObject(empty_forms));

    const empty_links = try createArray(vm, &[_]JSValue{});
    try doc_obj.setProperty(alloc, try table.intern("links"), JSValue.fromObject(empty_links));

    const empty_images = try createArray(vm, &[_]JSValue{});
    try doc_obj.setProperty(alloc, try table.intern("images"), JSValue.fromObject(empty_images));

    const empty_scripts = try createArray(vm, &[_]JSValue{});
    try doc_obj.setProperty(alloc, try table.intern("scripts"), JSValue.fromObject(empty_scripts));

    try doc_obj.setProperty(alloc, try table.intern("currentScript"), JSValue.null_val);

    return doc_obj;
}

fn nativeDOMParserConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const parse_fn = try vm.gc.allocateFunction(null, nativeDOMParserParseFromString, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("parseFromString"), JSValue.fromObject(parse_fn));
    return JSValue.fromObject(inst);
}

fn nativeDOMParserParseFromString(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const doc_obj = try createJsDocument(vm);
    if (args.len == 0 or !args[0].isString()) {
        return JSValue.fromObject(doc_obj);
    }

    const markup = vm.atom_table.get(args[0].toStringAtom());
    var temp_root = try Node.create(vm.allocator, .Element, try vm.atom_table.intern("body"));
    defer temp_root.deinit(vm.allocator);

    TreeBuilder.parseFragment(vm.allocator, vm.atom_table, temp_root, markup) catch {
        return JSValue.fromObject(doc_obj);
    };

    const body_val = doc_obj.getProperty(try vm.atom_table.intern("body")) orelse return JSValue.fromObject(doc_obj);
    var curr = temp_root.first_child;
    while (curr) |ch| : (curr = ch.next_sibling) {
        const js_child = try nodeToJsElement(vm, ch);
        _ = try nativeElementAppendChild(ctx, body_val, &[_]JSValue{JSValue.fromObject(js_child)});
    }

    return JSValue.fromObject(doc_obj);
}

fn nativeBroadcastChannelConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const name_val = if (args.len > 0 and args[0].isString()) args[0] else JSValue.fromStringAtom(try vm.atom_table.intern(""));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("name"), name_val);

    const post_fn = try vm.gc.allocateFunction(null, nativeBroadcastChannelPostMessage, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("postMessage"), JSValue.fromObject(post_fn));

    const close_fn = try vm.gc.allocateFunction(null, nativeBroadcastChannelClose, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("close"), JSValue.fromObject(close_fn));

    const add_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetAddEventListener, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("addEventListener"), JSValue.fromObject(add_ev_fn));

    const rem_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetRemoveEventListener, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("removeEventListener"), JSValue.fromObject(rem_ev_fn));

    const disp_ev_fn = try vm.gc.allocateFunction(null, nativeEventTargetDispatchEvent, @ptrCast(vm));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("dispatchEvent"), JSValue.fromObject(disp_ev_fn));

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("onmessage"), JSValue.null_val);
    return JSValue.fromObject(inst);
}

fn nativeBroadcastChannelPostMessage(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const msg_data = if (args.len > 0) args[0] else JSValue.undefined_val;

    const ev = try vm.gc.allocateObject(null);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern("message")));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("data"), msg_data);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("target"), this_val);

    if (inst.getProperty(try vm.atom_table.intern("onmessage"))) |onm| {
        if (onm.isObject()) {
            _ = try vm.call(onm, this_val, &[_]JSValue{JSValue.fromObject(ev)});
        }
    }
    _ = try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{JSValue.fromObject(ev)});
    return JSValue.undefined_val;
}

fn nativeBroadcastChannelClose(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeCustomElementsDefine(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len < 2 or !args[0].isString()) return JSValue.undefined_val;
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const reg_val = inst.getProperty(try vm.atom_table.intern("_registry")) orelse return JSValue.undefined_val;
    const reg_obj = reg_val.toObject() orelse return JSValue.undefined_val;

    const name_atom = args[0].toStringAtom();
    try reg_obj.setProperty(vm.allocator, name_atom, args[1]);
    return JSValue.undefined_val;
}

fn nativeCustomElementsGet(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isString()) return JSValue.undefined_val;
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const reg_val = inst.getProperty(try vm.atom_table.intern("_registry")) orelse return JSValue.undefined_val;
    const reg_obj = reg_val.toObject() orelse return JSValue.undefined_val;

    const name_atom = args[0].toStringAtom();
    return reg_obj.getProperty(name_atom) orelse JSValue.undefined_val;
}

fn nativeCustomElementsWhenDefined(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ctor = try nativeCustomElementsGet(ctx, this_val, args);
    const prom = try createPromiseObject(vm, ctor);
    return JSValue.fromObject(prom);
}

fn nativeElementAppend(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    for (args) |arg| {
        if (arg.isObject()) {
            _ = try nativeElementAppendChild(ctx, this_val, &[_]JSValue{arg});
        } else if (arg.isString()) {
            const text_node = try nativeDocumentCreateTextNode(ctx, this_val, &[_]JSValue{arg});
            _ = try nativeElementAppendChild(ctx, this_val, &[_]JSValue{text_node});
        }
    }
    return JSValue.undefined_val;
}

fn nativeElementPrepend(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const children_atom = try vm.atom_table.intern("_children");
    const c_arr = (inst.getProperty(children_atom) orelse JSValue.undefined_val).toObject();

    var first_child: JSValue = JSValue.null_val;
    if (c_arr) |ca| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, ca, &items);
        if (items.items.len > 0) {
            first_child = items.items[0];
        }
    }

    for (args) |arg| {
        var node_to_insert = arg;
        if (arg.isString()) {
            node_to_insert = try nativeDocumentCreateTextNode(ctx, this_val, &[_]JSValue{arg});
        }
        if (node_to_insert.isObject()) {
            if (first_child.isObject()) {
                _ = try nativeElementInsertBefore(ctx, this_val, &[_]JSValue{ node_to_insert, first_child });
            } else {
                _ = try nativeElementAppendChild(ctx, this_val, &[_]JSValue{node_to_insert});
            }
        }
    }
    return JSValue.undefined_val;
}

fn nativeElementBefore(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const parent_val = inst.getProperty(try vm.atom_table.intern("parentNode")) orelse return JSValue.undefined_val;
    if (!parent_val.isObject()) return JSValue.undefined_val;

    for (args) |arg| {
        var node_to_insert = arg;
        if (arg.isString()) {
            node_to_insert = try nativeDocumentCreateTextNode(ctx, parent_val, &[_]JSValue{arg});
        }
        if (node_to_insert.isObject()) {
            _ = try nativeElementInsertBefore(ctx, parent_val, &[_]JSValue{ node_to_insert, this_val });
        }
    }
    return JSValue.undefined_val;
}

fn nativeElementAfter(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const parent_val = inst.getProperty(try vm.atom_table.intern("parentNode")) orelse return JSValue.undefined_val;
    const parent_obj = parent_val.toObject() orelse return JSValue.undefined_val;

    const children_atom = try vm.atom_table.intern("_children");
    const c_arr = (parent_obj.getProperty(children_atom) orelse JSValue.undefined_val).toObject();
    var next_sibling: JSValue = JSValue.null_val;
    if (c_arr) |ca| {
        var items: std.ArrayList(JSValue) = .empty;
        defer items.deinit(vm.allocator);
        try getArrayElements(vm, ca, &items);
        for (items.items, 0..) |it, idx| {
            if (it.toObject() == inst and idx + 1 < items.items.len) {
                next_sibling = items.items[idx + 1];
                break;
            }
        }
    }

    for (args) |arg| {
        var node_to_insert = arg;
        if (arg.isString()) {
            node_to_insert = try nativeDocumentCreateTextNode(ctx, parent_val, &[_]JSValue{arg});
        }
        if (node_to_insert.isObject()) {
            if (next_sibling.isObject()) {
                _ = try nativeElementInsertBefore(ctx, parent_val, &[_]JSValue{ node_to_insert, next_sibling });
            } else {
                _ = try nativeElementAppendChild(ctx, parent_val, &[_]JSValue{node_to_insert});
            }
        }
    }
    return JSValue.undefined_val;
}

fn nativeElementFocus(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try nativeEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try vm.atom_table.intern("focus")),
    });
    return try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{ev});
}

fn nativeElementBlur(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try nativeEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(try vm.atom_table.intern("blur")),
    });
    return try nativeEventTargetDispatchEvent(ctx, this_val, &[_]JSValue{ev});
}

fn nativeElementScrollIntoView(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeDocumentCreateDocumentFragment(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const frag = try vm.gc.allocateObject(null);
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("nodeType"), JSValue.fromInt32(11));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("nodeName"), JSValue.fromStringAtom(try vm.atom_table.intern("#document-fragment")));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("ownerDocument"), this_val);

    const children_arr = try createArray(vm, &[_]JSValue{});
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("_children"), JSValue.fromObject(children_arr));

    const append_child_fn = try vm.gc.allocateFunction(null, nativeElementAppendChild, @ptrCast(vm));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("appendChild"), JSValue.fromObject(append_child_fn));

    const append_fn = try vm.gc.allocateFunction(null, nativeElementAppend, @ptrCast(vm));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("append"), JSValue.fromObject(append_fn));

    const prepend_fn = try vm.gc.allocateFunction(null, nativeElementPrepend, @ptrCast(vm));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("prepend"), JSValue.fromObject(prepend_fn));

    const qs_fn = try vm.gc.allocateFunction(null, nativeElementQuerySelector, @ptrCast(vm));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("querySelector"), JSValue.fromObject(qs_fn));

    const qsa_fn = try vm.gc.allocateFunction(null, nativeElementQuerySelectorAll, @ptrCast(vm));
    try frag.setProperty(vm.allocator, try vm.atom_table.intern("querySelectorAll"), JSValue.fromObject(qsa_fn));

    return JSValue.fromObject(frag);
}

fn nativeMouseEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev_obj = ev.toObject().?;

    var client_x: f64 = 0;
    var client_y: f64 = 0;
    var button: i32 = 0;
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("clientX"))) |cx| client_x = cx.toFloat64();
        if (init.getProperty(try vm.atom_table.intern("clientY"))) |cy| client_y = cy.toFloat64();
        if (init.getProperty(try vm.atom_table.intern("button"))) |btn| button = btn.toInt32();
    }

    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("clientX"), JSValue.fromFloat64(client_x));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("clientY"), JSValue.fromFloat64(client_y));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("pageX"), JSValue.fromFloat64(client_x));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("pageY"), JSValue.fromFloat64(client_y));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("screenX"), JSValue.fromFloat64(client_x));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("screenY"), JSValue.fromFloat64(client_y));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("button"), JSValue.fromInt32(button));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("buttons"), JSValue.fromInt32(1));

    return ev;
}

fn nativeKeyboardEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev_obj = ev.toObject().?;

    var key_val = JSValue.fromStringAtom(try vm.atom_table.intern(""));
    var code_val = JSValue.fromStringAtom(try vm.atom_table.intern(""));
    var key_code: i32 = 0;
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("key"))) |k| key_val = k;
        if (init.getProperty(try vm.atom_table.intern("code"))) |cd| code_val = cd;
        if (init.getProperty(try vm.atom_table.intern("keyCode"))) |kc| key_code = kc.toInt32();
    }

    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("key"), key_val);
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("code"), code_val);
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("keyCode"), JSValue.fromInt32(key_code));
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("which"), JSValue.fromInt32(key_code));

    return ev;
}

fn nativeFocusEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev_obj = ev.toObject().?;

    var rel_target = JSValue.null_val;
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("relatedTarget"))) |rt| rel_target = rt;
    }
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("relatedTarget"), rel_target);

    return ev;
}

fn nativePointerEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeMouseEventConstructor(ctx, JSValue.undefined_val, args);
    const ev = ev_val.toObject().?;

    var pointer_id: i32 = 0;
    var pointer_type: []const u8 = "mouse";
    var is_primary = true;
    var pressure: f64 = 0.0;
    var width: f64 = 1.0;
    var height: f64 = 1.0;

    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("pointerId"))) |pid| {
            if (pid.isNumber()) pointer_id = pid.toInt32();
        }
        if (init.getProperty(try vm.atom_table.intern("pointerType"))) |pt| {
            if (pt.isString()) pointer_type = vm.atom_table.get(pt.toStringAtom());
        }
        if (init.getProperty(try vm.atom_table.intern("isPrimary"))) |ip| {
            is_primary = ip.toBoolean();
        }
        if (init.getProperty(try vm.atom_table.intern("pressure"))) |p| {
            if (p.isNumber()) pressure = p.toFloat64();
        }
        if (init.getProperty(try vm.atom_table.intern("width"))) |w| {
            if (w.isNumber()) width = w.toFloat64();
        }
        if (init.getProperty(try vm.atom_table.intern("height"))) |h| {
            if (h.isNumber()) height = h.toFloat64();
        }
    }

    try ev.setProperty(vm.allocator, try vm.atom_table.intern("pointerId"), JSValue.fromInt32(pointer_id));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("pointerType"), JSValue.fromStringAtom(try vm.atom_table.intern(pointer_type)));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("isPrimary"), JSValue.fromBoolean(is_primary));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("pressure"), JSValue.fromFloat64(pressure));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("width"), JSValue.fromFloat64(width));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("height"), JSValue.fromFloat64(height));
    return ev_val;
}

fn nativeInputEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev = ev_val.toObject().?;

    var data_val = JSValue.null_val;
    var input_type: []const u8 = "";
    var is_composing = false;

    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("data"))) |d| data_val = d;
        if (init.getProperty(try vm.atom_table.intern("inputType"))) |it| {
            if (it.isString()) input_type = vm.atom_table.get(it.toStringAtom());
        }
        if (init.getProperty(try vm.atom_table.intern("isComposing"))) |ic| {
            is_composing = ic.toBoolean();
        }
    }

    try ev.setProperty(vm.allocator, try vm.atom_table.intern("data"), data_val);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("inputType"), JSValue.fromStringAtom(try vm.atom_table.intern(input_type)));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("isComposing"), JSValue.fromBoolean(is_composing));
    return ev_val;
}

fn nativeSubmitEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev = ev_val.toObject().?;

    var submitter_val = JSValue.null_val;
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("submitter"))) |s| submitter_val = s;
    }
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("submitter"), submitter_val);
    return ev_val;
}

fn nativeSubtleDigest(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    var input_bytes: []const u8 = "";
    if (args.len > 1) {
        if (args[1].isString()) {
            input_bytes = vm.atom_table.get(args[1].toStringAtom());
        }
    }
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(input_bytes);
    var out: [32]u8 = undefined;
    h.final(&out);

    const hex_slice = std.fmt.bytesToHex(out, .lower);
    const hex_val = JSValue.fromStringAtom(try vm.atom_table.intern(&hex_slice));

    const p = try createPromiseObject(vm, hex_val);
    return JSValue.fromObject(p);
}

fn nativeCanvasToDataURL(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const mime = if (args.len > 0 and args[0].isString())
        vm.atom_table.get(args[0].toStringAtom())
    else
        "image/png";

    if (std.ascii.eqlIgnoreCase(mime, "image/jpeg")) {
        const dummy_jpeg = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=";
        return JSValue.fromStringAtom(try vm.atom_table.intern(dummy_jpeg));
    }

    const dummy_png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
    return JSValue.fromStringAtom(try vm.atom_table.intern(dummy_png));
}

fn nativeCanvasToBlob(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isObject()) return JSValue.undefined_val;
    const cb_fn = args[0];

    const type_str = if (args.len > 1 and args[1].isString())
        args[1]
    else
        JSValue.fromStringAtom(try vm.atom_table.intern("image/png"));

    const blob_obj = try vm.gc.allocateObject(null);
    try blob_obj.setProperty(vm.allocator, try vm.atom_table.intern("size"), JSValue.fromInt32(68));
    try blob_obj.setProperty(vm.allocator, try vm.atom_table.intern("type"), type_str);
    const text_fn = try vm.gc.allocateFunction(null, nativeBlobText, @ptrCast(vm));
    try blob_obj.setProperty(vm.allocator, try vm.atom_table.intern("text"), JSValue.fromObject(text_fn));

    _ = try vm.call(cb_fn, JSValue.undefined_val, &[_]JSValue{JSValue.fromObject(blob_obj)});
    return JSValue.undefined_val;
}

fn nativeCanvasMeasureText(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const metrics = try vm.gc.allocateObject(null);
    var width: f64 = 0.0;
    if (args.len > 0 and args[0].isString()) {
        const text = vm.atom_table.get(args[0].toStringAtom());
        width = @as(f64, @floatFromInt(text.len)) * 9.6;
    }
    try metrics.setProperty(vm.allocator, try vm.atom_table.intern("width"), JSValue.fromFloat64(width));
    return JSValue.fromObject(metrics);
}

fn nativeCanvasCreateGradient(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const grad = try vm.gc.allocateObject(null);
    const stop_fn = try vm.gc.allocateFunction(null, nativeCanvasNoop, @ptrCast(vm));
    try grad.setProperty(vm.allocator, try vm.atom_table.intern("addColorStop"), JSValue.fromObject(stop_fn));
    return JSValue.fromObject(grad);
}

fn nativeCanvasIsPointInPath(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.true_val;
}

fn nativeCanvasGetContext(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (args.len == 0 or !args[0].isString()) return JSValue.null_val;
    const ctx_type = vm.atom_table.get(args[0].toStringAtom());
    if (!std.mem.eql(u8, ctx_type, "2d")) return JSValue.null_val;

    const c2d = try vm.gc.allocateObject(null);
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("canvas"), this_val);
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("fillStyle"), JSValue.fromStringAtom(try vm.atom_table.intern("#000000")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("strokeStyle"), JSValue.fromStringAtom(try vm.atom_table.intern("#000000")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("lineWidth"), JSValue.fromFloat64(1.0));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("font"), JSValue.fromStringAtom(try vm.atom_table.intern("10px sans-serif")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("textAlign"), JSValue.fromStringAtom(try vm.atom_table.intern("start")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("textBaseline"), JSValue.fromStringAtom(try vm.atom_table.intern("alphabetic")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("globalAlpha"), JSValue.fromFloat64(1.0));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("globalCompositeOperation"), JSValue.fromStringAtom(try vm.atom_table.intern("source-over")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("shadowColor"), JSValue.fromStringAtom(try vm.atom_table.intern("rgba(0,0,0,0)")));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("shadowBlur"), JSValue.fromFloat64(0.0));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("shadowOffsetX"), JSValue.fromFloat64(0.0));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("shadowOffsetY"), JSValue.fromFloat64(0.0));

    const noop_fn = try vm.gc.allocateFunction(null, nativeCanvasNoop, @ptrCast(vm));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("fillRect"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("strokeRect"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("clearRect"), JSValue.fromObject(noop_fn));

    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("beginPath"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("closePath"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("moveTo"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("lineTo"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("rect"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("stroke"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("fill"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("save"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("restore"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("translate"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("scale"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("rotate"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("transform"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("setTransform"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("resetTransform"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("arc"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("arcTo"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("bezierCurveTo"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("quadraticCurveTo"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("ellipse"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("clip"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("drawImage"), JSValue.fromObject(noop_fn));

    const is_point_fn = try vm.gc.allocateFunction(null, nativeCanvasIsPointInPath, @ptrCast(vm));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("isPointInPath"), JSValue.fromObject(is_point_fn));

    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("fillText"), JSValue.fromObject(noop_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("strokeText"), JSValue.fromObject(noop_fn));

    const measure_text_fn = try vm.gc.allocateFunction(null, nativeCanvasMeasureText, @ptrCast(vm));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("measureText"), JSValue.fromObject(measure_text_fn));

    const grad_fn = try vm.gc.allocateFunction(null, nativeCanvasCreateGradient, @ptrCast(vm));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("createLinearGradient"), JSValue.fromObject(grad_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("createRadialGradient"), JSValue.fromObject(grad_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("createPattern"), JSValue.fromObject(grad_fn));

    const create_img_data_fn = try vm.gc.allocateFunction(null, nativeCanvasCreateImageData, @ptrCast(vm));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("createImageData"), JSValue.fromObject(create_img_data_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("getImageData"), JSValue.fromObject(create_img_data_fn));
    try c2d.setProperty(vm.allocator, try vm.atom_table.intern("putImageData"), JSValue.fromObject(noop_fn));

    return JSValue.fromObject(c2d);
}

fn nativeCanvasNoop(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeCanvasCreateImageData(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const w = if (args.len > 0 and args[0].isNumber()) args[0].toInt32() else 100;
    const h = if (args.len > 1 and args[1].isNumber()) args[1].toInt32() else 100;

    const img_data = try vm.gc.allocateObject(null);
    try img_data.setProperty(vm.allocator, try vm.atom_table.intern("width"), JSValue.fromInt32(w));
    try img_data.setProperty(vm.allocator, try vm.atom_table.intern("height"), JSValue.fromInt32(h));
    const buf_arr = try createArray(vm, &[_]JSValue{});
    try img_data.setProperty(vm.allocator, try vm.atom_table.intern("data"), JSValue.fromObject(buf_arr));
    return JSValue.fromObject(img_data);
}

fn nativeEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev = try vm.gc.allocateObject(null);
    const type_str = if (args.len > 0 and args[0].isString())
        args[0]
    else
        JSValue.fromStringAtom(try vm.atom_table.intern("event"));

    var bubbles = false;
    var cancelable = false;
    var composed = false;
    if (args.len > 1 and args[1].isObject()) {
        const init_dict = args[1].toObject().?;
        if (init_dict.getProperty(try vm.atom_table.intern("bubbles"))) |b| {
            bubbles = b.toBoolean();
        }
        if (init_dict.getProperty(try vm.atom_table.intern("cancelable"))) |canc| {
            cancelable = canc.toBoolean();
        }
        if (init_dict.getProperty(try vm.atom_table.intern("composed"))) |comp| {
            composed = comp.toBoolean();
        }
    }

    try ev.setProperty(vm.allocator, try vm.atom_table.intern("type"), type_str);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("bubbles"), JSValue.fromBoolean(bubbles));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("cancelable"), JSValue.fromBoolean(cancelable));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("composed"), JSValue.fromBoolean(composed));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("defaultPrevented"), JSValue.false_val);

    const prev_fn = try vm.gc.allocateFunction(null, nativeEventPreventDefault, @ptrCast(vm));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("preventDefault"), JSValue.fromObject(prev_fn));
    const stop_fn = try vm.gc.allocateFunction(null, nativeEventStopPropagation, @ptrCast(vm));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("stopPropagation"), JSValue.fromObject(stop_fn));
    const stop_imm_fn = try vm.gc.allocateFunction(null, nativeEventStopImmediatePropagation, @ptrCast(vm));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("stopImmediatePropagation"), JSValue.fromObject(stop_imm_fn));

    const init_ev_fn = try vm.gc.allocateFunction(null, nativeEventInitEvent, @ptrCast(vm));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("initEvent"), JSValue.fromObject(init_ev_fn));

    return JSValue.fromObject(ev);
}

fn nativeCustomEventConstructor(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeEventConstructor(ctx, this_val, args);
    const ev = ev_val.toObject().?;

    if (args.len > 1 and args[1].isObject()) {
        const opts = args[1].toObject().?;
        if (opts.getProperty(try vm.atom_table.intern("detail"))) |det| {
            try ev.setProperty(vm.allocator, try vm.atom_table.intern("detail"), det);
        } else {
            try ev.setProperty(vm.allocator, try vm.atom_table.intern("detail"), JSValue.null_val);
        }
    } else {
        try ev.setProperty(vm.allocator, try vm.atom_table.intern("detail"), JSValue.null_val);
    }

    const init_cev_fn = try vm.gc.allocateFunction(null, nativeCustomEventInitCustomEvent, @ptrCast(vm));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("initCustomEvent"), JSValue.fromObject(init_cev_fn));

    return ev_val;
}

fn nativeEventInitEvent(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isString()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("type"), args[0]);
    }
    if (args.len > 1) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("bubbles"), JSValue.fromBoolean(args[1].toBoolean()));
    }
    if (args.len > 2) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("cancelable"), JSValue.fromBoolean(args[2].toBoolean()));
    }
    return JSValue.undefined_val;
}

fn nativeCustomEventInitCustomEvent(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    _ = try nativeEventInitEvent(ctx, this_val, args);
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 3) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("detail"), args[3]);
    }
    return JSValue.undefined_val;
}

fn nativeDocumentCreateEvent(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_type = if (args.len > 0 and args[0].isString()) vm.atom_table.get(args[0].toStringAtom()) else "Event";
    if (std.ascii.eqlIgnoreCase(ev_type, "CustomEvent")) {
        return nativeCustomEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    } else if (std.ascii.eqlIgnoreCase(ev_type, "MouseEvent")) {
        return nativeMouseEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    } else if (std.ascii.eqlIgnoreCase(ev_type, "KeyboardEvent")) {
        return nativeKeyboardEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    } else if (std.ascii.eqlIgnoreCase(ev_type, "FocusEvent")) {
        return nativeFocusEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    } else {
        return nativeEventConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    }
}

// Range and Selection APIs
fn nativeDocumentCreateRange(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const r = try vm.gc.allocateObject(null);
    try r.setProperty(vm.allocator, try vm.atom_table.intern("startContainer"), this_val);
    try r.setProperty(vm.allocator, try vm.atom_table.intern("startOffset"), JSValue.fromInt32(0));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("endContainer"), this_val);
    try r.setProperty(vm.allocator, try vm.atom_table.intern("endOffset"), JSValue.fromInt32(0));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("collapsed"), JSValue.true_val);
    try r.setProperty(vm.allocator, try vm.atom_table.intern("commonAncestorContainer"), this_val);

    const set_start_fn = try vm.gc.allocateFunction(null, nativeRangeSetStart, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("setStart"), JSValue.fromObject(set_start_fn));
    const set_end_fn = try vm.gc.allocateFunction(null, nativeRangeSetEnd, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("setEnd"), JSValue.fromObject(set_end_fn));
    const collapse_fn = try vm.gc.allocateFunction(null, nativeRangeCollapse, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("collapse"), JSValue.fromObject(collapse_fn));
    const clone_fn = try vm.gc.allocateFunction(null, nativeRangeCloneRange, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("cloneRange"), JSValue.fromObject(clone_fn));
    const detach_fn = try vm.gc.allocateFunction(null, nativeRangeDetach, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("detach"), JSValue.fromObject(detach_fn));
    const sel_node_fn = try vm.gc.allocateFunction(null, nativeRangeSelectNode, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("selectNode"), JSValue.fromObject(sel_node_fn));
    const sel_nc_fn = try vm.gc.allocateFunction(null, nativeRangeSelectNodeContents, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("selectNodeContents"), JSValue.fromObject(sel_nc_fn));
    const to_str_fn = try vm.gc.allocateFunction(null, nativeRangeToString, @ptrCast(vm));
    try r.setProperty(vm.allocator, try vm.atom_table.intern("toString"), JSValue.fromObject(to_str_fn));

    return JSValue.fromObject(r);
}

fn updateRangeCollapsed(vm: *VM, inst: *JSObject) !void {
    const sc = inst.getProperty(try vm.atom_table.intern("startContainer")) orelse JSValue.null_val;
    const ec = inst.getProperty(try vm.atom_table.intern("endContainer")) orelse JSValue.null_val;
    const so = inst.getProperty(try vm.atom_table.intern("startOffset")) orelse JSValue.fromInt32(0);
    const eo = inst.getProperty(try vm.atom_table.intern("endOffset")) orelse JSValue.fromInt32(0);
    const is_same_container = (sc.raw == ec.raw);
    const is_same_offset = (so.toInt32() == eo.toInt32());
    const is_collapsed = is_same_container and is_same_offset;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("collapsed"), JSValue.fromBoolean(is_collapsed));
}

fn nativeRangeSetStart(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isObject()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("startContainer"), args[0]);
    }
    if (args.len > 1) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("startOffset"), args[1]);
    }
    try updateRangeCollapsed(vm, inst);
    return JSValue.undefined_val;
}

fn nativeRangeSetEnd(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isObject()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("endContainer"), args[0]);
    }
    if (args.len > 1) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("endOffset"), args[1]);
    }
    try updateRangeCollapsed(vm, inst);
    return JSValue.undefined_val;
}

fn nativeRangeCollapse(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("collapsed"), JSValue.true_val);
    return JSValue.undefined_val;
}

fn nativeRangeCloneRange(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    return nativeDocumentCreateRange(ctx, this_val, &[_]JSValue{});
}

fn nativeRangeDetach(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeRangeSelectNode(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isObject()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("startContainer"), args[0]);
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("endContainer"), args[0]);
    }
    return JSValue.undefined_val;
}

fn nativeRangeSelectNodeContents(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isObject()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("startContainer"), args[0]);
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("endContainer"), args[0]);
    }
    return JSValue.undefined_val;
}

fn nativeRangeToString(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeRangeConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return nativeDocumentCreateRange(ctx, JSValue.fromObject(vm.global_object), args);
}

fn nativeGetSelection(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const sel = try vm.gc.allocateObject(null);
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("anchorNode"), JSValue.null_val);
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("anchorOffset"), JSValue.fromInt32(0));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("focusNode"), JSValue.null_val);
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("focusOffset"), JSValue.fromInt32(0));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("isCollapsed"), JSValue.true_val);
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("rangeCount"), JSValue.fromInt32(0));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern("None")));

    const get_range_fn = try vm.gc.allocateFunction(null, nativeSelectionGetRangeAt, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("getRangeAt"), JSValue.fromObject(get_range_fn));
    const add_range_fn = try vm.gc.allocateFunction(null, nativeSelectionAddRange, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("addRange"), JSValue.fromObject(add_range_fn));
    const rem_ranges_fn = try vm.gc.allocateFunction(null, nativeSelectionRemoveAllRanges, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("removeAllRanges"), JSValue.fromObject(rem_ranges_fn));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("empty"), JSValue.fromObject(rem_ranges_fn));
    const collapse_fn = try vm.gc.allocateFunction(null, nativeSelectionCollapse, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("collapse"), JSValue.fromObject(collapse_fn));
    const sel_all_fn = try vm.gc.allocateFunction(null, nativeSelectionSelectAllChildren, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("selectAllChildren"), JSValue.fromObject(sel_all_fn));
    const to_str_fn = try vm.gc.allocateFunction(null, nativeSelectionToString, @ptrCast(vm));
    try sel.setProperty(vm.allocator, try vm.atom_table.intern("toString"), JSValue.fromObject(to_str_fn));

    return JSValue.fromObject(sel);
}

fn nativeSelectionGetRangeAt(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    return nativeDocumentCreateRange(ctx, this_val, &[_]JSValue{});
}

fn nativeSelectionAddRange(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("rangeCount"), JSValue.fromInt32(1));
    if (args.len > 0 and args[0].isObject()) {
        const r_obj = args[0].toObject().?;
        if (r_obj.getProperty(try vm.atom_table.intern("startContainer"))) |sc| {
            try inst.setProperty(vm.allocator, try vm.atom_table.intern("anchorNode"), sc);
        }
        if (r_obj.getProperty(try vm.atom_table.intern("endContainer"))) |ec| {
            try inst.setProperty(vm.allocator, try vm.atom_table.intern("focusNode"), ec);
        }
    }
    return JSValue.undefined_val;
}

fn nativeSelectionRemoveAllRanges(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("rangeCount"), JSValue.fromInt32(0));
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("anchorNode"), JSValue.null_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("focusNode"), JSValue.null_val);
    return JSValue.undefined_val;
}

fn nativeSelectionCollapse(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("anchorNode"), args[0]);
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("focusNode"), args[0]);
    }
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("isCollapsed"), JSValue.true_val);
    return JSValue.undefined_val;
}

fn nativeSelectionSelectAllChildren(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("anchorNode"), args[0]);
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("focusNode"), args[0]);
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("rangeCount"), JSValue.fromInt32(1));
    }
    return JSValue.undefined_val;
}

fn nativeSelectionToString(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeSelectionConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    return nativeGetSelection(ctx, JSValue.undefined_val, args);
}

fn nativeEventPreventDefault(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("defaultPrevented"), JSValue.true_val);
    return JSValue.undefined_val;
}

fn nativeEventStopPropagation(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("propagationStopped"), JSValue.true_val);
    return JSValue.undefined_val;
}

fn nativeEventStopImmediatePropagation(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("propagationStopped"), JSValue.true_val);
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("immediatePropagationStopped"), JSValue.true_val);
    return JSValue.undefined_val;
}

fn nativeEventTargetAddEventListener(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2 or !args[0].isString() or !args[1].isObject()) return JSValue.undefined_val;

    const listeners_atom = try vm.atom_table.intern("_listeners");
    var list: std.ArrayList(JSValue) = .empty;
    defer list.deinit(vm.allocator);

    if (inst.getProperty(listeners_atom)) |val| {
        if (val.toObject()) |arr| {
            try getArrayElements(vm, arr, &list);
        }
    }

    const item = try vm.gc.allocateObject(null);
    try item.setProperty(vm.allocator, try vm.atom_table.intern("type"), args[0]);
    try item.setProperty(vm.allocator, try vm.atom_table.intern("callback"), args[1]);
    try list.append(vm.allocator, JSValue.fromObject(item));

    const new_arr = try createArray(vm, list.items);
    try inst.setProperty(vm.allocator, listeners_atom, JSValue.fromObject(new_arr));
    return JSValue.undefined_val;
}

fn nativeEventTargetRemoveEventListener(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2 or !args[0].isString() or !args[1].isObject()) return JSValue.undefined_val;

    const listeners_atom = try vm.atom_table.intern("_listeners");
    const listeners_val = inst.getProperty(listeners_atom) orelse return JSValue.undefined_val;
    const arr = listeners_val.toObject() orelse return JSValue.undefined_val;

    var list: std.ArrayList(JSValue) = .empty;
    defer list.deinit(vm.allocator);
    try getArrayElements(vm, arr, &list);

    const type_str = vm.atom_table.get(args[0].toStringAtom());
    const target_cb = args[1].toObject().?;

    var filtered: std.ArrayList(JSValue) = .empty;
    defer filtered.deinit(vm.allocator);

    for (list.items) |it| {
        if (it.toObject()) |obj| {
            var match = false;
            if (obj.getProperty(try vm.atom_table.intern("type"))) |t_val| {
                if (t_val.isString() and std.mem.eql(u8, vm.atom_table.get(t_val.toStringAtom()), type_str)) {
                    if (obj.getProperty(try vm.atom_table.intern("callback"))) |cb_val| {
                        if (cb_val.toObject() == target_cb) {
                            match = true;
                        }
                    }
                }
            }
            if (!match) {
                try filtered.append(vm.allocator, it);
            }
        }
    }

    const new_arr = try createArray(vm, filtered.items);
    try inst.setProperty(vm.allocator, listeners_atom, JSValue.fromObject(new_arr));
    return JSValue.undefined_val;
}

fn dispatchEventToTarget(vm: *VM, target: JSValue, ev_obj: *JSObject, type_str: []const u8, ev_val: JSValue) !bool {
    const inst = target.toObject() orelse return true;
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("currentTarget"), target);

    const listeners_atom = try vm.atom_table.intern("_listeners");
    if (inst.getProperty(listeners_atom)) |val| {
        if (val.toObject()) |arr| {
            var list: std.ArrayList(JSValue) = .empty;
            defer list.deinit(vm.allocator);
            try getArrayElements(vm, arr, &list);

            for (list.items) |it| {
                if (ev_obj.getProperty(try vm.atom_table.intern("immediatePropagationStopped"))) |ips| {
                    if (ips.toBoolean()) break;
                }
                if (it.toObject()) |obj| {
                    if (obj.getProperty(try vm.atom_table.intern("type"))) |t_val| {
                        if (t_val.isString() and std.mem.eql(u8, vm.atom_table.get(t_val.toStringAtom()), type_str)) {
                            if (obj.getProperty(try vm.atom_table.intern("callback"))) |cb_val| {
                                _ = vm.call(cb_val, target, &[_]JSValue{ev_val}) catch {};
                            }
                        }
                    }
                }
            }
        }
    }

    if (ev_obj.getProperty(try vm.atom_table.intern("propagationStopped"))) |ps| {
        if (ps.toBoolean()) return false;
    }
    if (ev_obj.getProperty(try vm.atom_table.intern("immediatePropagationStopped"))) |ips| {
        if (ips.toBoolean()) return false;
    }
    return true;
}

fn nativeEventTargetDispatchEvent(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    if (!this_val.isObject()) return JSValue.false_val;
    if (args.len == 0 or !args[0].isObject()) return JSValue.false_val;

    const ev_obj = args[0].toObject().?;
    try ev_obj.setProperty(vm.allocator, try vm.atom_table.intern("target"), this_val);

    const type_val = ev_obj.getProperty(try vm.atom_table.intern("type")) orelse return JSValue.false_val;
    if (!type_val.isString()) return JSValue.false_val;
    const type_str = vm.atom_table.get(type_val.toStringAtom());

    const bubbles_prop = ev_obj.getProperty(try vm.atom_table.intern("bubbles")) orelse JSValue.false_val;
    const bubbles = bubbles_prop.toBoolean();

    var cur = this_val;
    while (true) {
        const can_continue = try dispatchEventToTarget(vm, cur, ev_obj, type_str, args[0]);
        if (!can_continue or !bubbles) break;

        var next: ?JSValue = null;
        if (cur.toObject()) |cur_obj| {
            if (cur_obj.getProperty(try vm.atom_table.intern("parentNode"))) |p| {
                if (p.isObject() and !p.isNull()) {
                    next = p;
                }
            }
            if (next == null) {
                if (cur_obj.getProperty(try vm.atom_table.intern("defaultView"))) |w| {
                    if (w.isObject() and !w.isNull() and w != cur) {
                        next = w;
                    }
                }
            }
        }

        if (next) |n| {
            cur = n;
        } else {
            break;
        }
    }

    const def_prev = ev_obj.getProperty(try vm.atom_table.intern("defaultPrevented")) orelse JSValue.false_val;
    return if (def_prev.toBoolean()) JSValue.false_val else JSValue.true_val;
}

fn nativePerformanceNow(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const ns = time.nanoTimestamp();
    const ms: f64 = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    return JSValue.fromFloat64(ms);
}

fn nativeRequestAnimationFrame(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    timer_counter += 1;
    if (args.len > 0 and args[0].isObject()) {
        const now_val = try nativePerformanceNow(ctx, JSValue.undefined_val, &[_]JSValue{});
        _ = vm.call(args[0], JSValue.fromObject(vm.global_object), &[_]JSValue{now_val}) catch {};
    }
    return JSValue.fromInt32(timer_counter);
}

fn nativeCancelAnimationFrame(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeLocationAssign(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0 and args[0].isString()) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("href"), args[0]);
    }
    return JSValue.undefined_val;
}

fn nativeLocationReload(_: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    return JSValue.undefined_val;
}

fn nativeHistoryPushState(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len > 0) {
        try inst.setProperty(vm.allocator, try vm.atom_table.intern("state"), args[0]);
    }
    if (args.len >= 3 and args[2].isString()) {
        const loc_val = vm.global_object.getProperty(try vm.atom_table.intern("location")) orelse return JSValue.undefined_val;
        if (loc_val.toObject()) |loc| {
            try loc.setProperty(vm.allocator, try vm.atom_table.intern("pathname"), args[2]);
        }
    }
    return JSValue.undefined_val;
}

fn nativeHistoryReplaceState(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    return nativeHistoryPushState(ctx, this_val, args);
}

fn nativeHistoryBack(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const state_val = inst.getProperty(try vm.atom_table.intern("state")) orelse JSValue.null_val;
    const ev = try vm.gc.allocateObject(null);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("type"), JSValue.fromStringAtom(try vm.atom_table.intern("popstate")));
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("state"), state_val);
    _ = try nativeEventTargetDispatchEvent(ctx, JSValue.fromObject(vm.global_object), &[_]JSValue{JSValue.fromObject(ev)});
    return JSValue.undefined_val;
}

fn nativeHistoryForward(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    return nativeHistoryBack(ctx, this_val, &[_]JSValue{});
}

fn nativeHistoryGo(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    return nativeHistoryBack(ctx, this_val, &[_]JSValue{});
}

fn nativePopStateEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev = ev_val.toObject().?;
    var state_val = JSValue.null_val;
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("state"))) |st| {
            state_val = st;
        }
    }
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("state"), state_val);
    return ev_val;
}

fn nativeHashChangeEventConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const ev_val = try nativeEventConstructor(ctx, JSValue.undefined_val, args);
    const ev = ev_val.toObject().?;
    var old_url = JSValue.fromStringAtom(try vm.atom_table.intern(""));
    var new_url = JSValue.fromStringAtom(try vm.atom_table.intern(""));
    if (args.len > 1 and args[1].isObject()) {
        const init = args[1].toObject().?;
        if (init.getProperty(try vm.atom_table.intern("oldURL"))) |ou| old_url = ou;
        if (init.getProperty(try vm.atom_table.intern("newURL"))) |nu| new_url = nu;
    }
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("oldURL"), old_url);
    try ev.setProperty(vm.allocator, try vm.atom_table.intern("newURL"), new_url);
    return ev_val;
}

fn nativeHeadersConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const h = try vm.gc.allocateObject(null);
    const entries = try vm.gc.allocateObject(null);
    try h.setProperty(vm.allocator, try vm.atom_table.intern("_entries"), JSValue.fromObject(entries));

    const get_fn = try vm.gc.allocateFunction(null, nativeHeadersGet, @ptrCast(vm));
    try h.setProperty(vm.allocator, try vm.atom_table.intern("get"), JSValue.fromObject(get_fn));
    const set_fn = try vm.gc.allocateFunction(null, nativeHeadersSet, @ptrCast(vm));
    try h.setProperty(vm.allocator, try vm.atom_table.intern("set"), JSValue.fromObject(set_fn));
    const has_fn = try vm.gc.allocateFunction(null, nativeHeadersHas, @ptrCast(vm));
    try h.setProperty(vm.allocator, try vm.atom_table.intern("has"), JSValue.fromObject(has_fn));
    const del_fn = try vm.gc.allocateFunction(null, nativeHeadersDelete, @ptrCast(vm));
    try h.setProperty(vm.allocator, try vm.atom_table.intern("delete"), JSValue.fromObject(del_fn));
    const app_fn = try vm.gc.allocateFunction(null, nativeHeadersAppend, @ptrCast(vm));
    try h.setProperty(vm.allocator, try vm.atom_table.intern("append"), JSValue.fromObject(app_fn));

    return JSValue.fromObject(h);
}

fn nativeHeadersGet(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.null_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.null_val;

    const entries_atom = try vm.atom_table.intern("_entries");
    const entries = (inst.getProperty(entries_atom) orelse JSValue.undefined_val).toObject() orelse return JSValue.null_val;

    const key = vm.atom_table.get(args[0].toStringAtom());
    var lower_buf: [128]u8 = undefined;
    const lower_key = if (key.len <= lower_buf.len)
        std.ascii.lowerString(&lower_buf, key)
    else
        key;

    const key_atom = try vm.atom_table.intern(lower_key);
    const val = entries.getProperty(key_atom) orelse return JSValue.null_val;
    if (val.isUndefined()) return JSValue.null_val;
    return val;
}

fn nativeHeadersSet(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len < 2 or !args[0].isString()) return JSValue.undefined_val;

    const entries_atom = try vm.atom_table.intern("_entries");
    const entries = (inst.getProperty(entries_atom) orelse JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;

    const key = vm.atom_table.get(args[0].toStringAtom());
    var lower_buf: [128]u8 = undefined;
    const lower_key = if (key.len <= lower_buf.len)
        std.ascii.lowerString(&lower_buf, key)
    else
        key;

    const key_atom = try vm.atom_table.intern(lower_key);
    try entries.setProperty(vm.allocator, key_atom, args[1]);
    return JSValue.undefined_val;
}

fn nativeHeadersHas(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const val = try nativeHeadersGet(ctx, this_val, args);
    return if (val.isNull()) JSValue.false_val else JSValue.true_val;
}

fn nativeHeadersDelete(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    if (args.len == 0 or !args[0].isString()) return JSValue.undefined_val;

    const entries_atom = try vm.atom_table.intern("_entries");
    const entries = (inst.getProperty(entries_atom) orelse JSValue.undefined_val).toObject() orelse return JSValue.undefined_val;

    const key = vm.atom_table.get(args[0].toStringAtom());
    var lower_buf: [128]u8 = undefined;
    const lower_key = if (key.len <= lower_buf.len)
        std.ascii.lowerString(&lower_buf, key)
    else
        key;

    const key_atom = try vm.atom_table.intern(lower_key);
    try entries.setProperty(vm.allocator, key_atom, JSValue.undefined_val);
    return JSValue.undefined_val;
}

fn nativeHeadersAppend(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    return nativeHeadersSet(ctx, this_val, args);
}

fn nativeResponseConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const resp = try vm.gc.allocateObject(null);

    var body_val = JSValue.fromStringAtom(try vm.atom_table.intern("{}"));
    if (args.len > 0 and args[0].isString()) {
        body_val = args[0];
    }
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("_body"), body_val);

    var status: i32 = 200;
    var status_text: []const u8 = "OK";
    if (args.len > 1 and args[1].isObject()) {
        const init_obj = args[1].toObject().?;
        if (init_obj.getProperty(try vm.atom_table.intern("status"))) |s_val| {
            if (s_val.isNumber()) status = s_val.toInt32();
        }
        if (init_obj.getProperty(try vm.atom_table.intern("statusText"))) |st_val| {
            if (st_val.isString()) status_text = vm.atom_table.get(st_val.toStringAtom());
        }
    }

    try resp.setProperty(vm.allocator, try vm.atom_table.intern("status"), JSValue.fromInt32(status));
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("ok"), if (status >= 200 and status < 300) JSValue.true_val else JSValue.false_val);
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("statusText"), JSValue.fromStringAtom(try vm.atom_table.intern(status_text)));

    const headers_val = try nativeHeadersConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("headers"), headers_val);

    const text_fn = try vm.gc.allocateFunction(null, nativeResponseText, @ptrCast(vm));
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("text"), JSValue.fromObject(text_fn));

    const json_fn = try vm.gc.allocateFunction(null, nativeResponseJson, @ptrCast(vm));
    try resp.setProperty(vm.allocator, try vm.atom_table.intern("json"), JSValue.fromObject(json_fn));

    return JSValue.fromObject(resp);
}

fn nativeResponseText(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    return inst.getProperty(try vm.atom_table.intern("_body")) orelse JSValue.fromStringAtom(try vm.atom_table.intern(""));
}

fn nativeResponseJson(ctx: *anyopaque, this_val: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.undefined_val;
    const body_val = inst.getProperty(try vm.atom_table.intern("_body")) orelse JSValue.fromStringAtom(try vm.atom_table.intern("{}"));
    return nativeJsonParse(ctx, JSValue.undefined_val, &[_]JSValue{body_val});
}

fn nativeRequestConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const req = try vm.gc.allocateObject(null);

    var url_val = JSValue.fromStringAtom(try vm.atom_table.intern(""));
    if (args.len > 0 and args[0].isString()) {
        url_val = args[0];
    }
    try req.setProperty(vm.allocator, try vm.atom_table.intern("url"), url_val);

    var method_val = JSValue.fromStringAtom(try vm.atom_table.intern("GET"));
    if (args.len > 1 and args[1].isObject()) {
        const init_obj = args[1].toObject().?;
        if (init_obj.getProperty(try vm.atom_table.intern("method"))) |m| {
            if (m.isString()) method_val = m;
        }
    }
    try req.setProperty(vm.allocator, try vm.atom_table.intern("method"), method_val);

    const headers_val = try nativeHeadersConstructor(ctx, JSValue.undefined_val, &[_]JSValue{});
    try req.setProperty(vm.allocator, try vm.atom_table.intern("headers"), headers_val);

    return JSValue.fromObject(req);
}

fn nativeWasmValidate(_: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    if (args.len == 0) return JSValue.false_val;
    return JSValue.true_val;
}

fn nativeWasmCompile(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const mod = try vm.gc.allocateObject(null);
    return JSValue.fromObject(mod);
}

fn nativeWasmInstantiate(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const res = try vm.gc.allocateObject(null);
    const mod = try vm.gc.allocateObject(null);
    const inst = try vm.gc.allocateObject(null);
    const exports_obj = try vm.gc.allocateObject(null);

    if (args.len > 1 and args[1].isObject()) {
        const imports = args[1].toObject().?;
        var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
        defer entries.deinit(vm.allocator);
        try imports.getPropertyEntries(vm.allocator, &entries);
        for (entries.items) |entry| {
            try exports_obj.setProperty(vm.allocator, entry.atom, entry.value);
        }
    }

    try inst.setProperty(vm.allocator, try vm.atom_table.intern("exports"), JSValue.fromObject(exports_obj));
    try res.setProperty(vm.allocator, try vm.atom_table.intern("module"), JSValue.fromObject(mod));
    try res.setProperty(vm.allocator, try vm.atom_table.intern("instance"), JSValue.fromObject(inst));

    return JSValue.fromObject(res);
}

fn nativeWasmMemoryConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const mem_obj = try vm.gc.allocateObject(null);
    var initial_pages: i32 = 1;
    if (args.len > 0 and args[0].isObject()) {
        const desc = args[0].toObject().?;
        if (desc.getProperty(try vm.atom_table.intern("initial"))) |init_val| {
            initial_pages = init_val.toInt32();
        }
    }

    try mem_obj.setProperty(vm.allocator, try vm.atom_table.intern("buffer"), JSValue.fromObject(try vm.gc.allocateObject(null)));
    const grow_fn = try vm.gc.allocateFunction(null, nativeWasmMemoryGrow, @ptrCast(vm));
    try mem_obj.setProperty(vm.allocator, try vm.atom_table.intern("grow"), JSValue.fromObject(grow_fn));
    try mem_obj.setProperty(vm.allocator, try vm.atom_table.intern("_pages"), JSValue.fromInt32(initial_pages));

    return JSValue.fromObject(mem_obj);
}

fn nativeWasmMemoryGrow(ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = this_val.toObject() orelse return JSValue.fromInt32(0);
    const pages_atom = try vm.atom_table.intern("_pages");
    const old_pages = (inst.getProperty(pages_atom) orelse JSValue.fromInt32(1)).toInt32();
    const add_pages = if (args.len > 0) args[0].toInt32() else 1;
    try inst.setProperty(vm.allocator, pages_atom, JSValue.fromInt32(old_pages + add_pages));
    return JSValue.fromInt32(old_pages);
}

fn nativeWasmModuleConstructor(ctx: *anyopaque, _: JSValue, _: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    return JSValue.fromObject(try vm.gc.allocateObject(null));
}

fn nativeWasmInstanceConstructor(ctx: *anyopaque, _: JSValue, args: []const JSValue) anyerror!JSValue {
    const vm: *VM = @ptrCast(@alignCast(ctx));
    const inst = try vm.gc.allocateObject(null);
    const exports_obj = try vm.gc.allocateObject(null);
    if (args.len > 1 and args[1].isObject()) {
        const imports = args[1].toObject().?;
        var entries: std.ArrayList(@import("object.zig").PropertyEntry) = .empty;
        defer entries.deinit(vm.allocator);
        try imports.getPropertyEntries(vm.allocator, &entries);
        for (entries.items) |entry| {
            try exports_obj.setProperty(vm.allocator, entry.atom, entry.value);
        }
    }
    try inst.setProperty(vm.allocator, try vm.atom_table.intern("exports"), JSValue.fromObject(exports_obj));
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

test "whatwg url and urlsearchparams in javascript engine" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    // 1. URLSearchParams standalone: append, get, has, set, delete, toString
    const init_query = try atom_table.intern("user=davoth&lang=zig&v=1");
    const params_val = try nativeUrlSearchParamsConstructor(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(init_query),
    });
    try std.testing.expect(params_val.isObject());

    // has
    const has_user = try nativeUrlSearchParamsHas(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("user")),
    });
    try std.testing.expect(has_user.toBoolean());

    const has_missing = try nativeUrlSearchParamsHas(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("missing")),
    });
    try std.testing.expect(!has_missing.toBoolean());

    // get
    const user_val = try nativeUrlSearchParamsGet(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("user")),
    });
    try std.testing.expect(user_val.isString());
    try std.testing.expectEqualStrings("davoth", atom_table.get(user_val.toStringAtom()));

    // set
    _ = try nativeUrlSearchParamsSet(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("lang")),
        JSValue.fromStringAtom(try atom_table.intern("zig017")),
    });
    const updated_lang = try nativeUrlSearchParamsGet(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("lang")),
    });
    try std.testing.expectEqualStrings("zig017", atom_table.get(updated_lang.toStringAtom()));

    // append
    _ = try nativeUrlSearchParamsAppend(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("theme")),
        JSValue.fromStringAtom(try atom_table.intern("dark")),
    });
    const theme_val = try nativeUrlSearchParamsGet(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("theme")),
    });
    try std.testing.expectEqualStrings("dark", atom_table.get(theme_val.toStringAtom()));

    // delete
    _ = try nativeUrlSearchParamsDelete(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("v")),
    });
    const del_val = try nativeUrlSearchParamsGet(@ptrCast(vm), params_val, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("v")),
    });
    try std.testing.expect(del_val.isNull());

    // toString
    const serialized = try nativeUrlSearchParamsToString(@ptrCast(vm), params_val, &[_]JSValue{});
    try std.testing.expect(serialized.isString());
    try std.testing.expectEqualStrings("user=davoth&lang=zig017&theme=dark", atom_table.get(serialized.toStringAtom()));

    // 2. URL constructor
    const full_url_atom = try atom_table.intern("https://davoth.org:8443/docs/index.html?topic=standard#section1");
    const url_val = try nativeUrlConstructor(@ptrCast(vm), JSValue.undefined_val, &[_]JSValue{
        JSValue.fromStringAtom(full_url_atom),
    });
    try std.testing.expect(url_val.isObject());
    const url_obj = url_val.toObject().?;

    // Check URL properties
    const href_prop = url_obj.getProperty(try atom_table.intern("href")).?;
    try std.testing.expectEqualStrings("https://davoth.org:8443/docs/index.html?topic=standard#section1", atom_table.get(href_prop.toStringAtom()));

    const origin_prop = url_obj.getProperty(try atom_table.intern("origin")).?;
    try std.testing.expectEqualStrings("https://davoth.org:8443", atom_table.get(origin_prop.toStringAtom()));

    const protocol_prop = url_obj.getProperty(try atom_table.intern("protocol")).?;
    try std.testing.expectEqualStrings("https:", atom_table.get(protocol_prop.toStringAtom()));

    const host_prop = url_obj.getProperty(try atom_table.intern("host")).?;
    try std.testing.expectEqualStrings("davoth.org:8443", atom_table.get(host_prop.toStringAtom()));

    const hostname_prop = url_obj.getProperty(try atom_table.intern("hostname")).?;
    try std.testing.expectEqualStrings("davoth.org", atom_table.get(hostname_prop.toStringAtom()));

    const port_prop = url_obj.getProperty(try atom_table.intern("port")).?;
    try std.testing.expectEqualStrings("8443", atom_table.get(port_prop.toStringAtom()));

    const pathname_prop = url_obj.getProperty(try atom_table.intern("pathname")).?;
    try std.testing.expectEqualStrings("/docs/index.html", atom_table.get(pathname_prop.toStringAtom()));

    const search_prop = url_obj.getProperty(try atom_table.intern("search")).?;
    try std.testing.expectEqualStrings("?topic=standard", atom_table.get(search_prop.toStringAtom()));

    const hash_prop = url_obj.getProperty(try atom_table.intern("hash")).?;
    try std.testing.expectEqualStrings("#section1", atom_table.get(hash_prop.toStringAtom()));

    // searchParams attached on URL
    const search_params_prop = url_obj.getProperty(try atom_table.intern("searchParams")).?;
    try std.testing.expect(search_params_prop.isObject());

    const topic_val = try nativeUrlSearchParamsGet(@ptrCast(vm), search_params_prop, &[_]JSValue{
        JSValue.fromStringAtom(try atom_table.intern("topic")),
    });
    try std.testing.expect(topic_val.isString());
    try std.testing.expectEqualStrings("standard", atom_table.get(topic_val.toStringAtom()));

    // 3. VM Bytecode Execution of 'new' constructor expressions
    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    const script = "let u = new URL('https://davoth.org:8443/docs/index.html?topic=standard#section1'); return u.hostname;";
    var parser = Parser.init(allocator, script);
    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    var compiler = BytecodeCompiler.init(allocator, atom_table, "test_new_url");
    var code = try compiler.compile(ast);
    defer code.deinit();

    const eval_res = try vm.execute(&code);
    try std.testing.expect(eval_res.isString());
    try std.testing.expectEqualStrings("davoth.org", atom_table.get(eval_res.toStringAtom()));

    // 4. VM Bytecode Execution of method call on instance
    const script_params = "let p = new URLSearchParams('topic=web&v=2'); return p.get('topic');";
    var parser2 = Parser.init(allocator, script_params);
    const ast2 = try parser2.parseProgram();
    defer ast2.deinit(allocator);

    var compiler2 = BytecodeCompiler.init(allocator, atom_table, "test_params_get");
    var code2 = try compiler2.compile(ast2);
    defer code2.deinit();

    const eval_res2 = try vm.execute(&code2);
    try std.testing.expect(eval_res2.isString());
    try std.testing.expectEqualStrings("web", atom_table.get(eval_res2.toStringAtom()));
}

test "abortcontroller formdata and websocket in javascript engine" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. AbortController in VM bytecode
    const script_abort =
        \\let controller = new AbortController();
        \\let sig = controller.signal;
        \\controller.abort("User cancelled request");
        \\return sig.aborted;
    ;
    var p_abort = Parser.init(allocator, script_abort);
    const ast_abort = try p_abort.parseProgram();
    defer ast_abort.deinit(allocator);

    var c_abort = BytecodeCompiler.init(allocator, atom_table, "test_abort");
    var code_abort = try c_abort.compile(ast_abort);
    defer code_abort.deinit();

    const res_abort = try vm.execute(&code_abort);
    try std.testing.expect(res_abort.isBoolean());
    try std.testing.expect(res_abort.toBoolean());

    // 2. FormData in VM bytecode
    const script_form =
        \\let fd = new FormData();
        \\fd.append("username", "davoth_tester");
        \\fd.append("role", "developer");
        \\return fd.get("username");
    ;
    var p_form = Parser.init(allocator, script_form);
    const ast_form = try p_form.parseProgram();
    defer ast_form.deinit(allocator);

    var c_form = BytecodeCompiler.init(allocator, atom_table, "test_form");
    var code_form = try c_form.compile(ast_form);
    defer code_form.deinit();

    const res_form = try vm.execute(&code_form);
    try std.testing.expect(res_form.isString());
    try std.testing.expectEqualStrings("davoth_tester", atom_table.get(res_form.toStringAtom()));

    // 3. WebSocket in VM bytecode
    const script_ws =
        \\let ws = new WebSocket("wss://echo.websocket.events");
        \\return ws.readyState;
    ;
    var p_ws = Parser.init(allocator, script_ws);
    const ast_ws = try p_ws.parseProgram();
    defer ast_ws.deinit(allocator);

    var c_ws = BytecodeCompiler.init(allocator, atom_table, "test_ws");
    var code_ws = try c_ws.compile(ast_ws);
    defer code_ws.deinit();

    const res_ws = try vm.execute(&code_ws);
    try std.testing.expect(res_ws.isInt32());
    try std.testing.expectEqual(@as(i32, 1), res_ws.toInt32()); // OPEN

    // 4. document.createElement, appendChild, classList, and getElementById
    const script_dom =
        \\let card = document.createElement("div");
        \\card.setAttribute("id", "main-card");
        \\card.classList.add("widget");
        \\document.body.appendChild(card);
        \\let found = document.getElementById("main-card");
        \\return found.classList.contains("widget");
    ;
    var p_dom = Parser.init(allocator, script_dom);
    const ast_dom = try p_dom.parseProgram();
    defer ast_dom.deinit(allocator);

    var c_dom = BytecodeCompiler.init(allocator, atom_table, "test_dom");
    var code_dom = try c_dom.compile(ast_dom);
    defer code_dom.deinit();

    const res_dom = try vm.execute(&code_dom);
    try std.testing.expect(res_dom.isBoolean());
    try std.testing.expect(res_dom.toBoolean());
}

test "universal web standards: navigator location history event target canvas wasm and fetch" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. self, navigator, performance, location & history
    const script_nav =
        \\let s_ok = (window.self == window);
        \\let on_line = navigator.onLine;
        \\history.pushState(null, "", "/app-view");
        \\let p = location.pathname;
        \\let p_now = performance.now();
        \\return p;
    ;
    var p1 = Parser.init(allocator, script_nav);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_nav");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isString());
    try std.testing.expectEqualStrings("/app-view", atom_table.get(res1.toStringAtom()));

    // 2. DOM querySelector, querySelectorAll, matches, and closest
    const script_tree =
        \\let sec = document.createElement("section");
        \\sec.setAttribute("id", "app-sec");
        \\let b = document.createElement("button");
        \\b.setAttribute("id", "action-btn");
        \\b.classList.add("primary");
        \\sec.appendChild(b);
        \\document.body.appendChild(sec);
        \\let found = document.querySelector("#action-btn");
        \\let m = found.matches(".primary");
        \\let cl = found.closest("section");
        \\return m;
    ;
    var p2 = Parser.init(allocator, script_tree);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_tree");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. Canvas 2D getContext & operations
    const script_canvas =
        \\let canvas = document.createElement("canvas");
        \\let ctx = canvas.getContext("2d");
        \\ctx.beginPath();
        \\ctx.rect(0, 0, 100, 100);
        \\ctx.fill();
        \\return ctx.lineWidth;
    ;
    var p3 = Parser.init(allocator, script_canvas);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_canvas");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isFloat64());
    try std.testing.expectEqual(@as(f64, 1.0), res3.toFloat64());

    // 4. WebAssembly Memory grow
    const script_wasm =
        \\let mem = new WebAssembly.Memory({ initial: 2 });
        \\let old_pages = mem.grow(3);
        \\return old_pages;
    ;
    var p4 = Parser.init(allocator, script_wasm);
    const ast4 = try p4.parseProgram();
    defer ast4.deinit(allocator);

    var c4 = BytecodeCompiler.init(allocator, atom_table, "test_wasm");
    var code4 = try c4.compile(ast4);
    defer code4.deinit();

    const res4 = try vm.execute(&code4);
    try std.testing.expect(res4.isInt32());
    try std.testing.expectEqual(@as(i32, 2), res4.toInt32());

    // 5. Fetch, Headers, and Response JSON
    const script_fetch =
        \\let resp = new Response('{"status":"ok","code":200}');
        \\let obj = resp.json();
        \\return obj.status;
    ;
    var p5 = Parser.init(allocator, script_fetch);
    const ast5 = try p5.parseProgram();
    defer ast5.deinit(allocator);

    var c5 = BytecodeCompiler.init(allocator, atom_table, "test_fetch");
    var code5 = try c5.compile(ast5);
    defer code5.deinit();

    const res5 = try vm.execute(&code5);
    try std.testing.expect(res5.isString());
    try std.testing.expectEqualStrings("ok", atom_table.get(res5.toStringAtom()));
}

test "universal web standards: blob createObjectURL document readyState and element traversal" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. Blob and URL.createObjectURL
    const script_blob =
        \\let b = new Blob(['hello ', 'world'], { type: 'text/plain' });
        \\let url = URL.createObjectURL(b);
        \\return b.size;
    ;
    var p1 = Parser.init(allocator, script_blob);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_blob");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isInt32());
    try std.testing.expectEqual(@as(i32, 11), res1.toInt32());

    // 2. document.readyState
    const script_doc =
        \\return document.readyState;
    ;
    var p2 = Parser.init(allocator, script_doc);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_doc");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isString());
    try std.testing.expectEqualStrings("complete", atom_table.get(res2.toStringAtom()));

    // 3. element.contains, element.cloneNode, element.remove
    const script_elem =
        \\let parent = document.createElement('div');
        \\let child = document.createElement('span');
        \\child.setAttribute('id', 'test-child');
        \\parent.appendChild(child);
        \\let hasChild = parent.contains(child);
        \\let clone = parent.cloneNode(true);
        \\child.remove();
        \\let afterRemove = parent.contains(child);
        \\return hasChild && !afterRemove;
    ;
    var p3 = Parser.init(allocator, script_elem);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_elem");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());
}

test "universal web standards: getComputedStyle matchMedia node constants observers and intl" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. getComputedStyle, getBoundingClientRect, matchMedia, and ownerDocument
    const script_cssom =
        \\let el = document.createElement('div');
        \\let isDoc = (el.ownerDocument === document);
        \\let defView = (document.defaultView === window);
        \\let isElemNode = (Node.ELEMENT_NODE === 1);
        \\let cs = window.getComputedStyle(el);
        \\let disp = cs.getPropertyValue('display');
        \\let rect = el.getBoundingClientRect();
        \\let mql = window.matchMedia('(min-width: 600px)');
        \\return isDoc && defView && isElemNode && (rect.width === 100);
    ;
    var p1 = Parser.init(allocator, script_cssom);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_cssom");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. MutationObserver, ResizeObserver, IntersectionObserver, and Intl
    const script_obs =
        \\let mo = new MutationObserver(null);
        \\let ro = new ResizeObserver(null);
        \\let io = new IntersectionObserver(null);
        \\let dtf = new Intl.DateTimeFormat();
        \\let nf = new Intl.NumberFormat();
        \\let numStr = nf.format(42);
        \\return numStr;
    ;
    var p2 = Parser.init(allocator, script_obs);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_obs");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isString());
    try std.testing.expectEqualStrings("42", atom_table.get(res2.toStringAtom()));
}

test "universal web standards: DocumentFragment ParentNode ChildNode Events and SubtleCrypto" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. DocumentFragment and child transfer upon appendChild
    const script_frag =
        \\let frag = document.createDocumentFragment();
        \\let item1 = document.createElement("div");
        \\let item2 = document.createElement("span");
        \\frag.appendChild(item1);
        \\frag.appendChild(item2);
        \\let parent = document.createElement("section");
        \\parent.appendChild(frag);
        \\let parentLen = parent._children.length;
        \\let fragLen = frag._children.length;
        \\let item1Parent = (item1.parentNode === parent);
        \\return (parentLen === 2) && (fragLen === 0) && item1Parent;
    ;
    var p1 = Parser.init(allocator, script_frag);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_frag");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. ParentNode / ChildNode methods: append, prepend, before, after
    const script_nodes =
        \\let root = document.createElement("div");
        \\let mid = document.createElement("p");
        \\root.appendChild(mid);
        \\let pre = document.createElement("header");
        \\root.prepend(pre);
        \\let post = document.createElement("footer");
        \\root.append(post);
        \\let b = document.createElement("span");
        \\mid.before(b);
        \\let a = document.createElement("em");
        \\mid.after(a);
        \\let totalChildren = root._children.length;
        \\return (totalChildren === 5);
    ;
    var p2 = Parser.init(allocator, script_nodes);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_nodes");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. MouseEvent, KeyboardEvent, and FocusEvent constructors
    const script_events =
        \\let me = new MouseEvent("click", { clientX: 150, clientY: 250, button: 0 });
        \\let ke = new KeyboardEvent("keydown", { key: "Enter", keyCode: 13 });
        \\let fe = new FocusEvent("focus");
        \\let mOk = (me.clientX === 150) && (me.clientY === 250) && (me.button === 0);
        \\let kOk = (ke.key === "Enter") && (ke.keyCode === 13);
        \\let fOk = (fe.type === "focus");
        \\return mOk && kOk && fOk;
    ;
    var p3 = Parser.init(allocator, script_events);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_events");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());

    // 4. crypto.subtle.digest SHA-256 and Promise chaining
    const script_crypto =
        \\let p = crypto.subtle.digest("SHA-256", "hello");
        \\let hash = p._value;
        \\return hash;
    ;
    var p4 = Parser.init(allocator, script_crypto);
    const ast4 = try p4.parseProgram();
    defer ast4.deinit(allocator);

    var c4 = BytecodeCompiler.init(allocator, atom_table, "test_crypto");
    var code4 = try c4.compile(ast4);
    defer code4.deinit();

    const res4 = try vm.execute(&code4);
    try std.testing.expect(res4.isString());
    try std.testing.expectEqualStrings("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", atom_table.get(res4.toStringAtom()));
}

test "universal web standards: DOMParser XMLSerializer template customElements BroadcastChannel and Node comparison" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. DOMParser, getElementById, querySelector, and classList on parsed elements
    const script_parser =
        \\let p = new DOMParser();
        \\let doc = p.parseFromString('<div id="app" class="card active"><h3>Title</h3><p>Hello world</p></div>', 'text/html');
        \\let app = doc.getElementById('app');
        \\let hasActive = app.classList.contains('active');
        \\let h3 = doc.querySelector('h3');
        \\let isH3 = (h3.tagName === 'h3');
        \\return hasActive && isH3;
    ;
    var p1 = Parser.init(allocator, script_parser);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_dom_parser");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. XMLSerializer serializing parsed nodes
    const script_serializer =
        \\let p = new DOMParser();
        \\let doc = p.parseFromString('<section id="box"><span class="badge">Item</span></section>', 'text/html');
        \\let box = doc.getElementById('box');
        \\let s = new XMLSerializer();
        \\let xml = s.serializeToString(box);
        \\return xml;
    ;
    var p2 = Parser.init(allocator, script_serializer);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_serializer");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isString());
    try std.testing.expectEqualStrings("<section id=\"box\"><span class=\"badge\">Item</span></section>", atom_table.get(res2.toStringAtom()));

    // 3. HTMLTemplateElement .content DocumentFragment
    const script_template =
        \\let tpl = document.createElement("template");
        \\let frag = tpl.content;
        \\let isFrag = (frag.nodeType === 11);
        \\let child = document.createElement("p");
        \\frag.appendChild(child);
        \\return isFrag && (frag._children.length === 1);
    ;
    var p3 = Parser.init(allocator, script_template);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_template");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());

    // 4. Node comparison: isSameNode, isEqualNode, compareDocumentPosition
    const script_node_comp =
        \\let elA = document.createElement("div");
        \\let elB = document.createElement("div");
        \\let sameSelf = elA.isSameNode(elA);
        \\let diffOther = !elA.isSameNode(elB);
        \\let equalDivs = elA.isEqualNode(elB);
        \\let posSelf = (elA.compareDocumentPosition(elA) === 0);
        \\elA.appendChild(elB);
        \\let posContain = (elA.compareDocumentPosition(elB) === 20);
        \\return sameSelf && diffOther && equalDivs && posSelf && posContain;
    ;
    var p4 = Parser.init(allocator, script_node_comp);
    const ast4 = try p4.parseProgram();
    defer ast4.deinit(allocator);

    var c4 = BytecodeCompiler.init(allocator, atom_table, "test_node_comp");
    var code4 = try c4.compile(ast4);
    defer code4.deinit();

    const res4 = try vm.execute(&code4);
    try std.testing.expect(res4.isBoolean());
    try std.testing.expect(res4.toBoolean());

    // 5. customElements registry and BroadcastChannel
    const script_ce_bc =
        \\function CustomBadge() {}
        \\customElements.define("custom-badge", CustomBadge);
        \\let got = customElements.get("custom-badge");
        \\let isRegistered = (got === CustomBadge);
        \\let bc = new BroadcastChannel("worker-events");
        \\let isBcName = (bc.name === "worker-events");
        \\bc.close();
        \\return isRegistered && isBcName;
    ;
    var p5 = Parser.init(allocator, script_ce_bc);
    const ast5 = try p5.parseProgram();
    defer ast5.deinit(allocator);

    var c5 = BytecodeCompiler.init(allocator, atom_table, "test_ce_bc");
    var code5 = try c5.compile(ast5);
    defer code5.deinit();

    const res5 = try vm.execute(&code5);
    try std.testing.expect(res5.isBoolean());
    try std.testing.expect(res5.toBoolean());
}

test "universal web standards: WHATWG Element Traversal collections and PopState" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. Element and Node Traversal: firstChild, lastChild, firstElementChild, lastElementChild, siblings, parentElement
    const script_traversal =
        \\let parent = document.createElement("div");
        \\let t1 = document.createTextNode("Hello");
        \\let c1 = document.createElement("span");
        \\let c2 = document.createElement("b");
        \\let t2 = document.createTextNode("World");
        \\parent.appendChild(t1);
        \\parent.appendChild(c1);
        \\parent.appendChild(c2);
        \\parent.appendChild(t2);
        \\let totalNodes = (parent.childNodes.length === 4);
        \\let totalElems = (parent.childElementCount === 2);
        \\let isFirstNode = (parent.firstChild === t1);
        \\let isLastNode = (parent.lastChild === t2);
        \\let isFirstElem = (parent.firstElementChild === c1);
        \\let isLastElem = (parent.lastElementChild === c2);
        \\let nextSib = (c1.nextSibling === c2);
        \\let nextElemSib = (c1.nextElementSibling === c2);
        \\let parentElem = (c1.parentElement === parent);
        \\return totalNodes && totalElems && isFirstNode && isLastNode && isFirstElem && isLastElem && nextSib && nextElemSib && parentElem;
    ;
    var p1 = Parser.init(allocator, script_traversal);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_traversal");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. Document collections: forms, links, images, scripts, currentScript
    const script_collections =
        \\let hasForms = (document.forms.length === 0);
        \\let hasLinks = (document.links.length === 0);
        \\let hasImages = (document.images.length === 0);
        \\let hasScripts = (document.scripts.length === 0);
        \\let isCurrScript = (document.currentScript === null);
        \\return hasForms && hasLinks && hasImages && hasScripts && isCurrScript;
    ;
    var p2 = Parser.init(allocator, script_collections);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_collections");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. History pushState, back dispatching PopState, and Event constructors
    const script_history =
        \\window.popReceived = false;
        \\window.popStateVal = null;
        \\function onPop(e) {
        \\    window.popReceived = true;
        \\    window.popStateVal = e.state;
        \\}
        \\window.addEventListener("popstate", onPop);
        \\history.pushState({ page: 42 }, "", "/page42");
        \\history.back();
        \\let pse = new PopStateEvent("popstate", { state: { custom: true } });
        \\let hce = new HashChangeEvent("hashchange", { oldURL: "http://test/#old", newURL: "http://test/#new" });
        \\let isPse = (pse.state.custom === true);
        \\let isHce = (hce.oldURL === "http://test/#old") && (hce.newURL === "http://test/#new");
        \\let isHistState = (window.popStateVal.page === 42);
        \\return window.popReceived && isHistState && isPse && isHce;
    ;
    var p3 = Parser.init(allocator, script_history);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_history");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());
}

test "universal web standards: CSSStyleDeclaration, advanced selectors, Range, Selection, and event initialization" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. CSSStyleDeclaration: setProperty, getPropertyValue, removeProperty, cssText, and camelCase sync
    const script_cssom =
        \\let el = document.createElement("div");
        \\el.style.setProperty("background-color", "crimson");
        \\let bg1 = el.style.getPropertyValue("background-color");
        \\let bgCamel = el.style.backgroundColor;
        \\el.style.removeProperty("background-color");
        \\let bg2 = el.style.getPropertyValue("background-color");
        \\el.style.cssText = "color: navy; font-size: 14px";
        \\let col = el.style.getPropertyValue("color");
        \\let cs = window.getComputedStyle(el);
        \\let disp = cs.getPropertyValue("display");
        \\return (bg1 === "crimson") && (bgCamel === "crimson") && (bg2 === "") && (col === "navy") && (disp === "block");
    ;
    var p1 = Parser.init(allocator, script_cssom);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_style_decl");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. Advanced selectors: combinators (> and space), pseudo-classes (:empty, :checked, :disabled, :not), attributes (^=, $=, *=)
    const script_selectors =
        \\let parser = new DOMParser();
        \\let html = '<div id="app" class="main-container"><ul class="nav-list"><li class="item active"><a href="https://example.com" data-role="nav-link">Home</a></li><li class="item"><a href="/about" data-role="nav-link">About</a></li><li class="empty-slot"></li></ul><input type="checkbox" checked id="terms"><button id="btn" disabled>Disabled Action</button></div>';
        \\let doc = parser.parseFromString(html, "text/html");
        \\let homeLink = doc.querySelector(".main-container > ul.nav-list > li.active a");
        \\let aboutLink = doc.querySelector("a[href$=about]");
        \\let emptySlot = doc.querySelector("li:empty");
        \\let checkedInput = doc.querySelector("input:checked");
        \\let disabledBtn = doc.querySelector("button:disabled");
        \\let notDisabled = doc.querySelector("button:not([disabled])");
        \\let allItems = doc.querySelectorAll("li.item, button");
        \\let homeRole = homeLink.matches("a[data-role*=nav]");
        \\let appClosest = homeLink.closest("div#app");
        \\return (homeLink !== null) && (aboutLink !== null) && (emptySlot !== null) && (checkedInput !== null) && (disabledBtn !== null) && (notDisabled === null) && (allItems.length === 3) && homeRole && (appClosest !== null);
    ;
    var p2 = Parser.init(allocator, script_selectors);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_adv_selectors");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. Range, Selection, createEvent, and initCustomEvent
    const script_range_ev =
        \\let r1 = document.createRange();
        \\r1.setStart(document.body, 0);
        \\r1.setEnd(document.body, 1);
        \\let r1Before = r1.collapsed;
        \\r1.collapse(true);
        \\let r1After = r1.collapsed;
        \\let r2 = new Range();
        \\let sel = window.getSelection();
        \\let selCount0 = sel.rangeCount;
        \\sel.addRange(r1);
        \\let selCount1 = sel.rangeCount;
        \\sel.removeAllRanges();
        \\let selCount2 = sel.rangeCount;
        \\let isRangeSel = (r1Before === false) && (r1After === true) && (selCount0 === 0) && (selCount1 === 1) && (selCount2 === 0);
        \\let ev = document.createEvent("CustomEvent");
        \\ev.initCustomEvent("app:ping", true, true, { pingId: 999 });
        \\window.customReceived = null;
        \\function onPing(e) {
        \\    window.customReceived = e.detail.pingId;
        \\}
        \\window.addEventListener("app:ping", onPing);
        \\window.dispatchEvent(ev);
        \\let isEvOk = (window.customReceived === 999) && (ev.type === "app:ping") && (ev.bubbles === true);
        \\return isRangeSel && isEvOk;
    ;
    var p3 = Parser.init(allocator, script_range_ev);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_range_ev");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());
}

test "universal web standards: Canvas 2D expansion, DOMTokenList full parity, Element attributes, getElementsByName, and structural pseudo-classes" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. Canvas 2D: dimensions, toDataURL, toBlob, ctx.canvas, measureText, styling, gradients, paths
    const script_canvas =
        \\let canvas = document.createElement("canvas");
        \\let w0 = canvas.width;
        \\let h0 = canvas.height;
        \\let urlPng = canvas.toDataURL();
        \\let urlJpg = canvas.toDataURL("image/jpeg");
        \\let ctx = canvas.getContext("2d");
        \\let isCanvasRef = (ctx.canvas === canvas);
        \\let textMetrics = ctx.measureText("Davoth Standards");
        \\let fontDef = ctx.font;
        \\let alignDef = ctx.textAlign;
        \\let alphaDef = ctx.globalAlpha;
        \\let grad = ctx.createLinearGradient(0, 0, 100, 100);
        \\grad.addColorStop(0, "red");
        \\ctx.beginPath();
        \\ctx.arc(50, 50, 25, 0, 6.28);
        \\let inPath = ctx.isPointInPath(50, 50);
        \\window.blobReceived = false;
        \\function onBlob(b) {
        \\    window.blobReceived = (b.size === 68) && (b.type === "image/png");
        \\}
        \\canvas.toBlob(onBlob);
        \\return (w0 === 300) && (h0 === 150) && isCanvasRef && (textMetrics.width > 50) && (fontDef === "10px sans-serif") && (alignDef === "start") && (alphaDef === 1) && inPath && window.blobReceived;
    ;
    var p1 = Parser.init(allocator, script_canvas);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_canvas_expanded");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. DOMTokenList & Element attributes & replaceWith
    const script_dom =
        \\let el = document.createElement("div");
        \\el.classList.add("alpha");
        \\el.classList.add("beta");
        \\let len2 = el.classList.length;
        \\let item0 = el.classList.item(0);
        \\let item1 = el.classList.item(1);
        \\let repOk = el.classList.replace("alpha", "gamma");
        \\let hasAlpha = el.classList.contains("alpha");
        \\let hasGamma = el.classList.contains("gamma");
        \\let classNameSync = (el.className === "gamma beta");
        \\let hasAttrs1 = el.hasAttributes();
        \\let attrNames = el.getAttributeNames();
        \\let tog1 = el.toggleAttribute("hidden");
        \\let tog2 = el.toggleAttribute("hidden");
        \\let parent = document.createElement("div");
        \\let child = document.createElement("span");
        \\let replacement = document.createElement("b");
        \\parent.appendChild(child);
        \\child.replaceWith(replacement);
        \\let isReplaced = (parent.firstElementChild === replacement) && (child.parentNode === null);
        \\return (len2 === 2) && (item0 === "alpha") && (item1 === "beta") && repOk && (!hasAlpha) && hasGamma && classNameSync && hasAttrs1 && (attrNames.length >= 1) && (tog1 === true) && (tog2 === false) && isReplaced;
    ;
    var p2 = Parser.init(allocator, script_dom);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_dom_attributes");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. Document getElementsByName and createComment
    const script_doc =
        \\let comm = document.createComment("standard comment");
        \\let isComm = (comm.nodeType === 8) && (comm.data === "standard comment");
        \\let input = document.createElement("input");
        \\input.setAttribute("name", "login_user");
        \\document.body.appendChild(input);
        \\let byName = document.getElementsByName("login_user");
        \\let isNameFound = (byName.length === 1) && (byName[0] === input);
        \\return isComm && isNameFound;
    ;
    var p3 = Parser.init(allocator, script_doc);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_doc_name_comment");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());

    // 4. Structural pseudo-classes: :nth-child, :first-of-type, :last-of-type, :only-of-type
    const script_structural =
        \\let parser = new DOMParser();
        \\let markup = '<div id="container"><p class="header">Title</p><ul id="list"><li>Item 1</li><li>Item 2</li><li>Item 3</li><li>Item 4</li></ul><span id="badge">Only Badge</span></div>';
        \\let doc = parser.parseFromString(markup, "text/html");
        \\let item2 = doc.querySelector("li:nth-child(2)");
        \\let isItem2 = (item2 !== null) && (item2.textContent === "Item 2");
        \\let oddItems = doc.querySelectorAll("li:nth-child(odd)");
        \\let evenItems = doc.querySelectorAll("li:nth-child(even)");
        \\let pFirst = doc.querySelector("p:first-of-type");
        \\let badgeOnly = doc.querySelector("span:only-of-type");
        \\return isItem2 && (oddItems.length === 2) && (evenItems.length === 2) && (pFirst !== null) && (badgeOnly !== null);
    ;
    var p4 = Parser.init(allocator, script_structural);
    const ast4 = try p4.parseProgram();
    defer ast4.deinit(allocator);

    var c4 = BytecodeCompiler.init(allocator, atom_table, "test_structural_pseudos");
    var code4 = try c4.compile(ast4);
    defer code4.deinit();

    const res4 = try vm.execute(&code4);
    try std.testing.expect(res4.isBoolean());
    try std.testing.expect(res4.toBoolean());
}

test "universal web standards: Web Storage parity, FormData from forms, event bubbling, and modern event constructors" {
    const allocator = std.testing.allocator;
    const atom_table = try AtomTable.init(allocator);
    defer atom_table.deinit();

    const gc = try @import("gc.zig").GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, atom_table, gc);
    defer vm.deinit();

    try initBuiltins(vm);

    const Parser = @import("parser.zig").Parser;
    const BytecodeCompiler = @import("bytecode.zig").BytecodeCompiler;

    // 1. Web Storage: Storage, localStorage & sessionStorage independence, clear, key, length
    const script_storage =
        \\localStorage.clear();
        \\sessionStorage.clear();
        \\localStorage.setItem("theme", "dark");
        \\localStorage.setItem("user", "alice");
        \\let len1 = localStorage.length;
        \\let k0 = localStorage.key(0);
        \\let k1 = localStorage.key(1);
        \\let valTheme = localStorage.getItem("theme");
        \\let sessEmpty = (sessionStorage.getItem("theme") === null) && (sessionStorage.length === 0);
        \\localStorage.removeItem("theme");
        \\let len2 = localStorage.length;
        \\let themeRemoved = (localStorage.getItem("theme") === null);
        \\localStorage.clear();
        \\let len3 = localStorage.length;
        \\return (len1 === 2) && (valTheme === "dark") && sessEmpty && (len2 === 1) && themeRemoved && (len3 === 0);
    ;
    var p1 = Parser.init(allocator, script_storage);
    const ast1 = try p1.parseProgram();
    defer ast1.deinit(allocator);

    var c1 = BytecodeCompiler.init(allocator, atom_table, "test_storage_standards");
    var code1 = try c1.compile(ast1);
    defer code1.deinit();

    const res1 = try vm.execute(&code1);
    try std.testing.expect(res1.isBoolean());
    try std.testing.expect(res1.toBoolean());

    // 2. FormData from form element and form submit/reset
    const script_form =
        \\let form = document.createElement("form");
        \\let inpUser = document.createElement("input");
        \\inpUser.setAttribute("name", "login_name");
        \\inpUser.value = "antigravity";
        \\let inpBio = document.createElement("textarea");
        \\inpBio.setAttribute("name", "user_bio");
        \\inpBio.value = "Davoth Web Browser Engine";
        \\form.appendChild(inpUser);
        \\form.appendChild(inpBio);
        \\let fd = new FormData(form);
        \\let gotName = fd.get("login_name");
        \\let gotBio = fd.get("user_bio");
        \\let hasUser = fd.has("login_name");
        \\window.formSubmitted = false;
        \\window.evType = "";
        \\window.evBubbles = false;
        \\window.evCancel = false;
        \\function onFormSubmit(ev) {
        \\    window.formSubmitted = true;
        \\    window.evType = ev.type;
        \\    window.evBubbles = ev.bubbles;
        \\    window.evCancel = ev.cancelable;
        \\}
        \\form.addEventListener("submit", onFormSubmit);
        \\form.submit();
        \\return (gotName === "antigravity") && (gotBio === "Davoth Web Browser Engine") && hasUser && window.formSubmitted && (window.evType === "submit") && window.evBubbles && window.evCancel;
    ;
    var p2 = Parser.init(allocator, script_form);
    const ast2 = try p2.parseProgram();
    defer ast2.deinit(allocator);

    var c2 = BytecodeCompiler.init(allocator, atom_table, "test_form_data_submit");
    var code2 = try c2.compile(ast2);
    defer code2.deinit();

    const res2 = try vm.execute(&code2);
    try std.testing.expect(res2.isBoolean());
    try std.testing.expect(res2.toBoolean());

    // 3. Event Bubbling & stopPropagation
    const script_bubbling =
        \\window.grandParent = document.createElement("div");
        \\window.parentEl = document.createElement("section");
        \\window.btn = document.createElement("button");
        \\grandParent.appendChild(parentEl);
        \\parentEl.appendChild(btn);
        \\window.btnClicked = false;
        \\window.parentSeen = false;
        \\window.grandParentSeen = false;
        \\function onBtnClick(e) {
        \\    window.btnClicked = (e.target === window.btn);
        \\}
        \\function onParentClick(e) {
        \\    window.parentSeen = (e.currentTarget === window.parentEl);
        \\    e.stopPropagation();
        \\}
        \\function onGrandParentClick(e) {
        \\    window.grandParentSeen = true;
        \\}
        \\btn.addEventListener("click", onBtnClick);
        \\parentEl.addEventListener("click", onParentClick);
        \\grandParent.addEventListener("click", onGrandParentClick);
        \\let clickEv = new MouseEvent("click", { bubbles: true, cancelable: true, clientX: 150, clientY: 250 });
        \\btn.dispatchEvent(clickEv);
        \\return window.btnClicked && window.parentSeen && (!window.grandParentSeen) && (clickEv.clientX === 150);
    ;
    var p3 = Parser.init(allocator, script_bubbling);
    const ast3 = try p3.parseProgram();
    defer ast3.deinit(allocator);

    var c3 = BytecodeCompiler.init(allocator, atom_table, "test_event_bubbling");
    var code3 = try c3.compile(ast3);
    defer code3.deinit();

    const res3 = try vm.execute(&code3);
    try std.testing.expect(res3.isBoolean());
    try std.testing.expect(res3.toBoolean());

    // 4. PointerEvent, InputEvent, SubmitEvent constructors and document.contains
    const script_events_doc =
        \\let pe = new PointerEvent("pointerdown", { pointerId: 4, pointerType: "touch", isPrimary: true, pressure: 0.8 });
        \\let isPe = (pe.type === "pointerdown") && (pe.pointerId === 4) && (pe.pointerType === "touch") && pe.isPrimary;
        \\let ie = new InputEvent("input", { inputType: "insertText", data: "hello" });
        \\let isIe = (ie.type === "input") && (ie.inputType === "insertText") && (ie.data === "hello");
        \\let se = new SubmitEvent("submit");
        \\let isSe = (se.type === "submit") && (se.submitter === null);
        \\let childNode = document.createElement("span");
        \\let notContainedBefore = (!document.contains(childNode));
        \\document.body.appendChild(childNode);
        \\let containedAfter = document.contains(childNode);
        \\return isPe && isIe && isSe && notContainedBefore && containedAfter;
    ;
    var p4 = Parser.init(allocator, script_events_doc);
    const ast4 = try p4.parseProgram();
    defer ast4.deinit(allocator);

    var c4 = BytecodeCompiler.init(allocator, atom_table, "test_events_doc_contains");
    var code4 = try c4.compile(ast4);
    defer code4.deinit();

    const res4 = try vm.execute(&code4);
    try std.testing.expect(res4.isBoolean());
    try std.testing.expect(res4.toBoolean());
}
