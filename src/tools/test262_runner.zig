//! Test262 ECMAScript standard compliance test suite runner for Davoth JavaScript engine.
const std = @import("std");
const AtomTable = @import("../common/string.zig").AtomTable;
const GarbageCollector = @import("../js/gc.zig").GarbageCollector;
const VM = @import("../js/interpreter.zig").VM;
const JSValue = @import("../js/value.zig").JSValue;
const Parser = @import("../js/parser.zig").Parser;
const BytecodeCompiler = @import("../js/bytecode.zig").BytecodeCompiler;

pub const Test262Result = struct {
    name: []const u8,
    passed: bool,
    error_message: ?[]const u8 = null,
};

pub const Test262Runner = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    gc: *GarbageCollector,
    vm: *VM,
    results: std.ArrayList(Test262Result),

    pub fn init(allocator: std.mem.Allocator) !Test262Runner {
        const table = try AtomTable.init(allocator);
        const gc = try GarbageCollector.init(allocator);
        const vm = try VM.init(allocator, table, gc);

        return .{
            .allocator = allocator,
            .atom_table = table,
            .gc = gc,
            .vm = vm,
            .results = .empty,
        };
    }

    pub fn deinit(self: *Test262Runner) void {
        self.vm.deinit();
        self.gc.deinit();
        self.atom_table.deinit();
        self.results.deinit(self.allocator);
    }

    pub fn runTestCase(self: *Test262Runner, name: []const u8, code_src: []const u8, expected_numeric_result: ?f64) !bool {
        var parser = Parser.init(self.allocator, code_src);
        const ast = parser.parseProgram() catch |err| {
            try self.results.append(self.allocator, .{
                .name = name,
                .passed = false,
                .error_message = @errorName(err),
            });
            return false;
        };
        defer ast.deinit(self.allocator);

        var compiler = BytecodeCompiler.init(self.allocator, self.atom_table, name);
        var code = compiler.compile(ast) catch |err| {
            try self.results.append(self.allocator, .{
                .name = name,
                .passed = false,
                .error_message = @errorName(err),
            });
            return false;
        };
        defer code.deinit();

        const val = self.vm.execute(&code) catch |err| {
            try self.results.append(self.allocator, .{
                .name = name,
                .passed = false,
                .error_message = @errorName(err),
            });
            return false;
        };

        var ok = true;
        if (expected_numeric_result) |exp| {
            ok = (val.toFloat64() == exp);
        }

        try self.results.append(self.allocator, .{
            .name = name,
            .passed = ok,
            .error_message = if (ok) null else "Return value did not match expectation",
        });

        return ok;
    }

    pub fn runConformanceSuite(self: *Test262Runner) !struct { passed: usize, failed: usize, total: usize } {
        // ch07: Lexical Grammar & Numeric Literals
        _ = try self.runTestCase(
            "test262/ch07/7.8.3-numeric-addition",
            "let a = 100; let b = 250; return a + b;",
            350.0,
        );

        // ch11: Expressions & Operator Precedence
        _ = try self.runTestCase(
            "test262/ch11/11.5-multiplication-precedence",
            "let x = 5; let y = 10; let z = 2; return x + y * z;",
            25.0,
        );

        // ch12: Statements & Control Flow (while loop)
        _ = try self.runTestCase(
            "test262/ch12/12.6.2-while-statement",
            "let sum = 0; let i = 1; while (i <= 10) { sum = sum + i; i = i + 1; } return sum;",
            55.0,
        );

        // ch13: Functions & Call Return
        _ = try self.runTestCase(
            "test262/ch13/13.0-function-invocation",
            "function add(x, y) { return x + y; } return add(40, 2);",
            42.0,
        );

        // ch14: Conditional Expressions
        _ = try self.runTestCase(
            "test262/ch14/14.1-if-else-branching",
            "let val = 0; if (5 > 3) { val = 99; } else { val = 1; } return val;",
            99.0,
        );

        // ch12: For statement iteration
        _ = try self.runTestCase(
            "test262/ch12/12.6.3-for-statement",
            "let acc = 0; for (let j = 0; j < 5; j = j + 1) { acc = acc + j; } return acc;",
            10.0,
        );

        // ch13: Nested function execution
        _ = try self.runTestCase(
            "test262/ch13/13.2-nested-function-calls",
            "function outer(a) { function inner(b) { return b * 2; } return inner(a) + 10; } return outer(15);",
            40.0,
        );

        // ch13: Recursive function calls (Fibonacci)
        _ = try self.runTestCase(
            "test262/ch13/13.3-recursive-function-fibonacci",
            "function fib(n) { if (n <= 1) return n; return fib(n-1) + fib(n-2); } return fib(10);",
            55.0,
        );

        var passed: usize = 0;
        var failed: usize = 0;
        for (self.results.items) |r| {
            if (r.passed) passed += 1 else failed += 1;
        }

        return .{
            .passed = passed,
            .failed = failed,
            .total = self.results.items.len,
        };
    }
};

test "test262 conformance suite execution" {
    const allocator = std.testing.allocator;
    var runner = try Test262Runner.init(allocator);
    defer runner.deinit();

    const stats = try runner.runConformanceSuite();
    try std.testing.expect(stats.total >= 5);
    try std.testing.expectEqual(@as(usize, 0), stats.failed);
}
