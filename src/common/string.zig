//! Compact string interning (AtomTable) and UTF-8/UTF-16 encoding utilities.
const std = @import("std");
const Mutex = @import("sync.zig").Mutex;

pub const AtomId = enum(u32) {
    empty = 0,
    _,

    pub fn toU32(self: AtomId) u32 {
        return @intFromEnum(self);
    }

    pub fn fromU32(val: u32) AtomId {
        return @enumFromInt(val);
    }
};

pub const AtomTable = struct {
    allocator: std.mem.Allocator,
    atoms: std.ArrayList([]const u8),
    map: std.StringHashMap(AtomId),
    mutex: Mutex = .{},

    pub var global: ?*AtomTable = null;

    pub fn init(allocator: std.mem.Allocator) !*AtomTable {
        const self = try allocator.create(AtomTable);
        self.* = .{
            .allocator = allocator,
            .atoms = .empty,
            .map = std.StringHashMap(AtomId).init(allocator),
            .mutex = .{},
        };
        // ID 0 is empty string
        try self.atoms.append(allocator, "");
        try self.map.put("", AtomId.empty);
        return self;
    }

    pub fn deinit(self: *AtomTable) void {
        self.mutex.lock();
        for (self.atoms.items[1..]) |atom| {
            self.allocator.free(atom);
        }
        self.atoms.deinit(self.allocator);
        self.map.deinit();
        const alloc = self.allocator;
        self.mutex.unlock();
        alloc.destroy(self);
    }

    pub fn intern(self: *AtomTable, str: []const u8) !AtomId {
        if (str.len == 0) return AtomId.empty;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.get(str)) |id| {
            return id;
        }

        const copy = try self.allocator.dupe(u8, str);
        const new_id: AtomId = @enumFromInt(@as(u32, @truncate(self.atoms.items.len)));
        try self.atoms.append(self.allocator, copy);
        try self.map.put(copy, new_id);
        return new_id;
    }

    pub fn get(self: *AtomTable, id: AtomId) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        const idx = @intFromEnum(id);
        if (idx < self.atoms.items.len) {
            return self.atoms.items[idx];
        }
        return "";
    }
};

pub const Utf8Iterator = struct {
    bytes: []const u8,
    index: usize = 0,

    pub fn init(bytes: []const u8) Utf8Iterator {
        return .{ .bytes = bytes, .index = 0 };
    }

    pub fn next(self: *Utf8Iterator) ?u21 {
        if (self.index >= self.bytes.len) return null;
        const len = std.unicode.utf8ByteSequenceLength(self.bytes[self.index]) catch {
            self.index += 1;
            return 0xFFFD; // replacement character
        };
        if (self.index + len > self.bytes.len) {
            self.index = self.bytes.len;
            return 0xFFFD;
        }
        const cp = std.unicode.utf8Decode(self.bytes[self.index .. self.index + len]) catch 0xFFFD;
        self.index += len;
        return cp;
    }
};

pub fn utf8ToUtf16Le(allocator: std.mem.Allocator, utf8: []const u8) ![]u16 {
    var list: std.ArrayList(u16) = .empty;
    errdefer list.deinit(allocator);

    var it = Utf8Iterator.init(utf8);
    while (it.next()) |cp| {
        if (cp < 0x10000) {
            try list.append(allocator, @truncate(cp));
        } else {
            const high = @as(u16, @truncate(((cp - 0x10000) >> 10) + 0xD800));
            const low = @as(u16, @truncate(((cp - 0x10000) & 0x3FF) + 0xDC00));
            try list.append(allocator, high);
            try list.append(allocator, low);
        }
    }
    return list.toOwnedSlice(allocator);
}

pub fn utf16LeToUtf8(allocator: std.mem.Allocator, utf16: []const u16) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    while (i < utf16.len) {
        const c = utf16[i];
        i += 1;
        var cp: u21 = c;
        if (c >= 0xD800 and c <= 0xDBFF and i < utf16.len) {
            const next = utf16[i];
            if (next >= 0xDC00 and next <= 0xDFFF) {
                cp = (@as(u21, c - 0xD800) << 10) + @as(u21, next - 0xDC00) + 0x10000;
                i += 1;
            }
        }
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch continue;
        try list.appendSlice(allocator, buf[0..len]);
    }
    return list.toOwnedSlice(allocator);
}

test "atom table interning" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const id1 = try table.intern("div");
    const id2 = try table.intern("div");
    const id3 = try table.intern("span");

    try std.testing.expectEqual(id1, id2);
    try std.testing.expect(id1 != id3);
    try std.testing.expectEqualStrings("div", table.get(id1));
    try std.testing.expectEqualStrings("span", table.get(id3));
}

test "utf8 and utf16 conversion" {
    const allocator = std.testing.allocator;
    const original = "Hello 🌍 Davoth Browser!";
    const utf16 = try utf8ToUtf16Le(allocator, original);
    defer allocator.free(utf16);

    const back_to_utf8 = try utf16LeToUtf8(allocator, utf16);
    defer allocator.free(back_to_utf8);

    try std.testing.expectEqualStrings(original, back_to_utf8);
}
