//! JavaScript Debugger, Breakpoint Engine, and Interactive Console REPL.
//! Supports breakpoint stepping, console message levels (Log, Info, Warn, Error),
//! live expression evaluation, and $0 DOM node reference.

const std = @import("std");
const AtomTable = @import("../common/string.zig").AtomTable;
const AtomId = @import("../common/string.zig").AtomId;
const Node = @import("../dom/node.zig").Node;
const VM = @import("../js/interpreter.zig").VM;
const JSValue = @import("../js/value.zig").JSValue;
const Parser = @import("../js/parser.zig").Parser;
const BytecodeCompiler = @import("../js/bytecode.zig").BytecodeCompiler;
const time = @import("../common/time.zig");

pub const Breakpoint = struct {
    file_path: []const u8,
    line: u32,
    enabled: bool = true,
};

pub const ConsoleLogLevel = enum {
    Log,
    Info,
    Warn,
    Error,
    Debug,
};

pub const ConsoleMessage = struct {
    level: ConsoleLogLevel,
    text: []const u8,
    timestamp_ms: i64,

    pub fn deinit(self: *ConsoleMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

pub const JsConsole = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(ConsoleMessage),
    history: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) JsConsole {
        return .{
            .allocator = allocator,
            .messages = .empty,
            .history = .empty,
        };
    }

    pub fn deinit(self: *JsConsole) void {
        for (self.messages.items) |*m| {
            m.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);

        for (self.history.items) |h| {
            self.allocator.free(h);
        }
        self.history.deinit(self.allocator);
    }

    pub fn addMessage(self: *JsConsole, level: ConsoleLogLevel, text: []const u8) !void {
        try self.messages.append(self.allocator, .{
            .level = level,
            .text = try self.allocator.dupe(u8, text),
            .timestamp_ms = time.timestamp(),
        });
    }

    pub fn clear(self: *JsConsole) void {
        for (self.messages.items) |*m| {
            m.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();
    }

    /// Evaluates a JavaScript REPL expression and formats the output
    pub fn eval(
        self: *JsConsole,
        code_input: []const u8,
        vm_opt: ?*VM,
        table_opt: ?*AtomTable,
        selected_node_opt: ?*const Node,
    ) ![]u8 {
        const trimmed = std.mem.trim(u8, code_input, " \t\r\n");

        // Record in command history
        try self.history.append(self.allocator, try self.allocator.dupe(u8, trimmed));

        // 1. Built-in: clear()
        if (std.mem.eql(u8, trimmed, "clear()")) {
            self.clear();
            return self.allocator.dupe(u8, "Console was cleared");
        }

        // 2. Built-in: $0 (DevTools selected element shortcut)
        if (std.mem.eql(u8, trimmed, "$0")) {
            if (selected_node_opt) |node| {
                if (table_opt) |table| {
                    if (node.node_type == .Element) {
                        const tag = table.get(node.tag_name);
                        const id_atom = table.intern("id") catch null;
                        if (id_atom) |ia| {
                            if (node.getAttribute(ia)) |id_val| {
                                return std.fmt.allocPrint(self.allocator, "<{s} id=\"{s}\">", .{ tag, id_val });
                            }
                        }
                        return std.fmt.allocPrint(self.allocator, "<{s}>", .{tag});
                    }
                }
                return self.allocator.dupe(u8, "<selected node>");
            }
            return self.allocator.dupe(u8, "null");
        }

        // 3. Evaluate via JS Virtual Machine if available
        if (vm_opt) |vm| {
            if (table_opt) |table| {
                var parser = Parser.init(self.allocator, trimmed);
                const ast = parser.parseProgram() catch |err| {
                    const err_msg = try std.fmt.allocPrint(self.allocator, "Uncaught SyntaxError: Failed to parse input ({any})", .{err});
                    try self.addMessage(.Error, err_msg);
                    return err_msg;
                };
                defer ast.deinit(self.allocator);

                var compiler = BytecodeCompiler.init(self.allocator, table, "repl");
                var code_block = compiler.compile(ast) catch |err| {
                    const err_msg = try std.fmt.allocPrint(self.allocator, "Uncaught CompileError: {any}", .{err});
                    try self.addMessage(.Error, err_msg);
                    return err_msg;
                };
                defer code_block.deinit();

                const result = vm.execute(&code_block) catch |err| {
                    const err_msg = try std.fmt.allocPrint(self.allocator, "Uncaught RuntimeError: {any}", .{err});
                    try self.addMessage(.Error, err_msg);
                    return err_msg;
                };

                const formatted = try self.formatJSValue(result, table);
                try self.addMessage(.Log, formatted);
                return formatted;
            }
        }

        return self.allocator.dupe(u8, "undefined");
    }

    fn formatJSValue(self: *JsConsole, val: JSValue, table: *AtomTable) ![]u8 {
        switch (val.getType()) {
            .Undefined => return self.allocator.dupe(u8, "undefined"),
            .Null => return self.allocator.dupe(u8, "null"),
            .Boolean => return self.allocator.dupe(u8, if (val.toBoolean()) "true" else "false"),
            .Int32 => return std.fmt.allocPrint(self.allocator, "{d}", .{val.toInt32()}),
            .Float64 => {
                const f = val.toFloat64();
                if (std.math.isNan(f)) return self.allocator.dupe(u8, "NaN");
                if (std.math.isPositiveInf(f)) return self.allocator.dupe(u8, "Infinity");
                if (std.math.isNegativeInf(f)) return self.allocator.dupe(u8, "-Infinity");
                return std.fmt.allocPrint(self.allocator, "{d}", .{f});
            },
            .String => {
                const atom_val: u32 = @truncate(val.raw & 0xFFFF_FFFF);
                const atom_id: AtomId = @enumFromInt(atom_val);
                const str = table.get(atom_id);
                return std.fmt.allocPrint(self.allocator, "\"{s}\"", .{str});
            },
            .Object => return self.allocator.dupe(u8, "[object Object]"),
            .Symbol => return self.allocator.dupe(u8, "Symbol()"),
        }
    }
};

pub const JsDebugger = struct {
    allocator: std.mem.Allocator,
    breakpoints: std.ArrayList(Breakpoint),
    is_paused: bool = false,
    console: JsConsole,

    pub fn init(allocator: std.mem.Allocator) JsDebugger {
        return .{
            .allocator = allocator,
            .breakpoints = .empty,
            .is_paused = false,
            .console = JsConsole.init(allocator),
        };
    }

    pub fn deinit(self: *JsDebugger) void {
        for (self.breakpoints.items) |bp| {
            self.allocator.free(bp.file_path);
        }
        self.breakpoints.deinit(self.allocator);
        self.console.deinit();
    }

    pub fn setBreakpoint(self: *JsDebugger, file: []const u8, line: u32) !void {
        try self.breakpoints.append(self.allocator, .{
            .file_path = try self.allocator.dupe(u8, file),
            .line = line,
            .enabled = true,
        });
    }

    pub fn shouldBreak(self: *const JsDebugger, file: []const u8, line: u32) bool {
        for (self.breakpoints.items) |bp| {
            if (bp.enabled and bp.line == line and std.mem.eql(u8, bp.file_path, file)) {
                return true;
            }
        }
        return false;
    }
};

test "devtools debugger breakpoints and interactive console repl" {
    const allocator = std.testing.allocator;
    var dbg = JsDebugger.init(allocator);
    defer dbg.deinit();

    // 1. Breakpoint verification
    try dbg.setBreakpoint("app.js", 42);
    try std.testing.expect(dbg.shouldBreak("app.js", 42));
    try std.testing.expect(!dbg.shouldBreak("app.js", 43));
    try std.testing.expect(!dbg.shouldBreak("other.js", 42));

    // 2. Console messages
    try dbg.console.addMessage(.Log, "Application initialized");
    try dbg.console.addMessage(.Warn, "Deprecated CSS property");
    try dbg.console.addMessage(.Error, "Network connection timed out");

    try std.testing.expectEqual(@as(usize, 3), dbg.console.messages.items.len);
    try std.testing.expectEqual(ConsoleLogLevel.Error, dbg.console.messages.items[2].level);

    // 3. Clear console
    dbg.console.clear();
    try std.testing.expectEqual(@as(usize, 0), dbg.console.messages.items.len);

    // 4. Console REPL $0 shortcut
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const node = try Node.create(allocator, .Element, try table.intern("button"));
    defer node.deinit(allocator);
    try node.setAttribute(allocator, try table.intern("id"), "submit-btn");

    const r0 = try dbg.console.eval("$0", null, table, node);
    defer allocator.free(r0);
    try std.testing.expectEqualStrings("<button id=\"submit-btn\">", r0);

    // 5. Console History
    try std.testing.expectEqual(@as(usize, 1), dbg.console.history.items.len);
    try std.testing.expectEqualStrings("$0", dbg.console.history.items[0]);
}

test "devtools console repl javascript evaluation with vm" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const GarbageCollector = @import("../js/gc.zig").GarbageCollector;
    var gc = try GarbageCollector.init(allocator);
    defer gc.deinit();

    const vm = try VM.init(allocator, table, gc);
    defer vm.deinit();

    var console = JsConsole.init(allocator);
    defer console.deinit();

    // Arithmetic expression
    const res1 = try console.eval("10 + 32;", vm, table, null);
    defer allocator.free(res1);
    try std.testing.expectEqualStrings("42", res1);

    // Variable and assignment
    const res2 = try console.eval("let x = 100; x + 50;", vm, table, null);
    defer allocator.free(res2);
    try std.testing.expectEqualStrings("150", res2);

    // Check message log
    try std.testing.expect(console.messages.items.len >= 2);
}
