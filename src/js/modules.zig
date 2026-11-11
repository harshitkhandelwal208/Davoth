//! ES Modules loader, module record, and dependency resolution.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const JSValue = @import("value.zig").JSValue;
const CodeBlock = @import("bytecode.zig").CodeBlock;
const VM = @import("interpreter.zig").VM;

pub const ModuleStatus = enum {
    Unlinked,
    Linking,
    Linked,
    Evaluating,
    Evaluated,
};

pub const ModuleRecord = struct {
    allocator: std.mem.Allocator,
    specifier: []const u8,
    status: ModuleStatus = .Unlinked,
    exports: std.StringHashMap(JSValue),
    code: ?CodeBlock = null,

    pub fn init(allocator: std.mem.Allocator, specifier: []const u8) !*ModuleRecord {
        const mod = try allocator.create(ModuleRecord);
        mod.* = .{
            .allocator = allocator,
            .specifier = try allocator.dupe(u8, specifier),
            .status = .Unlinked,
            .exports = std.StringHashMap(JSValue).init(allocator),
            .code = null,
        };
        return mod;
    }

    pub fn deinit(self: *ModuleRecord) void {
        self.allocator.free(self.specifier);
        self.exports.deinit();
        if (self.code) |*c| c.deinit();
        self.allocator.destroy(self);
    }

    pub fn setExport(self: *ModuleRecord, name: []const u8, val: JSValue) !void {
        try self.exports.put(name, val);
    }

    pub fn getExport(self: *ModuleRecord, name: []const u8) ?JSValue {
        return self.exports.get(name);
    }
};

pub const ModuleLoader = struct {
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(*ModuleRecord),

    pub fn init(allocator: std.mem.Allocator) ModuleLoader {
        return .{
            .allocator = allocator,
            .modules = std.StringHashMap(*ModuleRecord).init(allocator),
        };
    }

    pub fn deinit(self: *ModuleLoader) void {
        var it = self.modules.valueIterator();
        while (it.next()) |mod| {
            mod.*.deinit();
        }
        self.modules.deinit();
    }

    pub fn registerModule(self: *ModuleLoader, specifier: []const u8) !*ModuleRecord {
        if (self.modules.get(specifier)) |existing| {
            return existing;
        }

        const mod = try ModuleRecord.init(self.allocator, specifier);
        try self.modules.put(mod.specifier, mod);
        return mod;
    }

    pub fn evaluateModule(self: *ModuleLoader, vm: *VM, specifier: []const u8) !JSValue {
        const mod = self.modules.get(specifier) orelse return error.ModuleNotFound;
        if (mod.status == .Evaluated) return JSValue.undefined_val;

        mod.status = .Evaluating;
        if (mod.code) |*code| {
            const res = try vm.execute(code);
            mod.status = .Evaluated;
            return res;
        }
        mod.status = .Evaluated;
        return JSValue.undefined_val;
    }
};

test "module record exports" {
    const allocator = std.testing.allocator;
    var loader = ModuleLoader.init(allocator);
    defer loader.deinit();

    const mod = try loader.registerModule("./math.js");
    try mod.setExport("version", JSValue.fromFloat64(2.0));

    const ver = mod.getExport("version").?;
    try std.testing.expectEqual(@as(f64, 2.0), ver.toFloat64());
}
