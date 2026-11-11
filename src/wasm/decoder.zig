//! WebAssembly binary decoder supporting sections and LEB128 parsing.
const std = @import("std");
const ValueType = @import("types.zig").ValueType;
const Limits = @import("types.zig").Limits;
const FuncType = @import("types.zig").FuncType;

pub const SectionId = enum(u8) {
    Custom = 0,
    Type = 1,
    Import = 2,
    Function = 3,
    Table = 4,
    Memory = 5,
    Global = 6,
    Export = 7,
    Start = 8,
    Element = 9,
    Code = 10,
    Data = 11,
};

pub const Export = struct {
    name: []const u8,
    kind: u8, // 0 = func, 1 = table, 2 = mem, 3 = global
    index: u32,
};

pub const FunctionBody = struct {
    local_count: u32,
    code: []const u8,
};

pub const WasmModule = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(FuncType),
    functions: std.ArrayList(u32), // type indices
    exports: std.ArrayList(Export),
    code_bodies: std.ArrayList(FunctionBody),
    memory_limits: ?Limits = null,

    pub fn deinit(self: *WasmModule) void {
        for (self.types.items) |t| {
            self.allocator.free(t.params);
            self.allocator.free(t.returns);
        }
        self.types.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        for (self.exports.items) |e| {
            self.allocator.free(e.name);
        }
        self.exports.deinit(self.allocator);
        self.code_bodies.deinit(self.allocator);
    }
};

pub const Decoder = struct {
    bytes: []const u8,
    cursor: usize = 0,

    pub fn init(bytes: []const u8) Decoder {
        return .{ .bytes = bytes, .cursor = 0 };
    }

    pub fn readUleb128(self: *Decoder) !u32 {
        var result: u32 = 0;
        var shift: u5 = 0;
        while (true) {
            if (self.cursor >= self.bytes.len) return error.UnexpectedEof;
            const b = self.bytes[self.cursor];
            self.cursor += 1;
            result |= @as(u32, b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
            if (shift >= 35) return error.InvalidLeb128;
        }
        return result;
    }

    pub fn readSleb128(self: *Decoder) !i32 {
        var result: i32 = 0;
        var shift: u5 = 0;
        var b: u8 = 0;
        while (true) {
            if (self.cursor >= self.bytes.len) return error.UnexpectedEof;
            b = self.bytes[self.cursor];
            self.cursor += 1;
            result |= @as(i32, b & 0x7F) << shift;
            shift += 7;
            if ((b & 0x80) == 0) break;
            if (shift >= 35) return error.InvalidLeb128;
        }
        if (shift < 32 and (b & 0x40) != 0) {
            result |= @as(i32, -1) << shift;
        }
        return result;
    }

    pub fn decodeModule(self: *Decoder, allocator: std.mem.Allocator) !WasmModule {
        if (self.bytes.len < 8) return error.InvalidWasmHeader;

        // Magic: 0x00 0x61 0x73 0x6d (\0asm)
        const magic = self.bytes[0..4];
        if (!std.mem.eql(u8, magic, "\x00asm")) return error.InvalidWasmMagic;

        // Version: 1
        const version = std.mem.readInt(u32, self.bytes[4..8], .little);
        if (version != 1) return error.UnsupportedWasmVersion;
        self.cursor = 8;

        var module = WasmModule{
            .allocator = allocator,
            .types = .empty,
            .functions = .empty,
            .exports = .empty,
            .code_bodies = .empty,
            .memory_limits = null,
        };
        errdefer module.deinit();

        while (self.cursor < self.bytes.len) {
            const sec_id_raw = self.bytes[self.cursor];
            self.cursor += 1;
            const sec_len = try self.readUleb128();
            const sec_end = self.cursor + sec_len;
            if (sec_end > self.bytes.len) return error.UnexpectedEof;

            const sec_id: SectionId = @enumFromInt(sec_id_raw);
            switch (sec_id) {
                .Type => {
                    const count = try self.readUleb128();
                    var i: u32 = 0;
                    while (i < count) : (i += 1) {
                        const form = self.bytes[self.cursor];
                        self.cursor += 1;
                        if (form != 0x60) return error.InvalidFunctionType;

                        const param_count = try self.readUleb128();
                        const params = try allocator.alloc(ValueType, param_count);
                        var p_idx: usize = 0;
                        while (p_idx < param_count) : (p_idx += 1) {
                            params[p_idx] = @enumFromInt(self.bytes[self.cursor]);
                            self.cursor += 1;
                        }

                        const ret_count = try self.readUleb128();
                        const returns = try allocator.alloc(ValueType, ret_count);
                        var r_idx: usize = 0;
                        while (r_idx < ret_count) : (r_idx += 1) {
                            returns[r_idx] = @enumFromInt(self.bytes[self.cursor]);
                            self.cursor += 1;
                        }

                        try module.types.append(allocator, .{ .params = params, .returns = returns });
                    }
                },
                .Function => {
                    const count = try self.readUleb128();
                    var i: u32 = 0;
                    while (i < count) : (i += 1) {
                        const type_idx = try self.readUleb128();
                        try module.functions.append(allocator, type_idx);
                    }
                },
                .Memory => {
                    const count = try self.readUleb128();
                    if (count > 0) {
                        const flags = self.bytes[self.cursor];
                        self.cursor += 1;
                        const min = try self.readUleb128();
                        var max: ?u32 = null;
                        if ((flags & 1) != 0) {
                            max = try self.readUleb128();
                        }
                        module.memory_limits = .{ .min = min, .max = max };
                    }
                },
                .Export => {
                    const count = try self.readUleb128();
                    var i: u32 = 0;
                    while (i < count) : (i += 1) {
                        const name_len = try self.readUleb128();
                        const name = try allocator.dupe(u8, self.bytes[self.cursor .. self.cursor + name_len]);
                        self.cursor += name_len;
                        const kind = self.bytes[self.cursor];
                        self.cursor += 1;
                        const index = try self.readUleb128();
                        try module.exports.append(allocator, .{
                            .name = name,
                            .kind = kind,
                            .index = index,
                        });
                    }
                },
                .Code => {
                    const count = try self.readUleb128();
                    var i: u32 = 0;
                    while (i < count) : (i += 1) {
                        const body_size = try self.readUleb128();
                        const body_start = self.cursor;
                        const local_vec_count = try self.readUleb128();
                        var total_locals: u32 = 0;
                        var lv: u32 = 0;
                        while (lv < local_vec_count) : (lv += 1) {
                            const l_count = try self.readUleb128();
                            _ = self.bytes[self.cursor]; // local type
                            self.cursor += 1;
                            total_locals += l_count;
                        }

                        const code_bytes = self.bytes[self.cursor .. body_start + body_size];
                        self.cursor = body_start + body_size;
                        try module.code_bodies.append(allocator, .{
                            .local_count = total_locals,
                            .code = code_bytes,
                        });
                    }
                },
                else => {
                    self.cursor = sec_end;
                },
            }
            self.cursor = sec_end;
        }

        return module;
    }
};

test "decode minimal wasm module" {
    const allocator = std.testing.allocator;
    // WASM binary with magic, version 1, and an empty Type section
    const wasm_bytes = "\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00";
    var decoder = Decoder.init(wasm_bytes);
    var mod = try decoder.decodeModule(allocator);
    defer mod.deinit();

    try std.testing.expectEqual(@as(usize, 1), mod.types.items.len);
    try std.testing.expectEqual(@as(usize, 0), mod.types.items[0].params.len);
    try std.testing.expectEqual(@as(usize, 0), mod.types.items[0].returns.len);
}
