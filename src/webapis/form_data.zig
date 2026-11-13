//! WHATWG FormData API implementation for multipart/form-data encoding and manipulation.
const std = @import("std");

pub const FormDataEntry = struct {
    name: []const u8,
    value: []const u8,
};

pub const FormData = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(FormDataEntry),

    pub fn init(allocator: std.mem.Allocator) FormData {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *FormData) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *FormData, name: []const u8, value: []const u8) !void {
        const n = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(n);
        const v = try self.allocator.dupe(u8, value);
        try self.entries.append(self.allocator, .{ .name = n, .value = v });
    }

    pub fn get(self: *const FormData, name: []const u8) ?[]const u8 {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn has(self: *const FormData, name: []const u8) bool {
        return self.get(name) != null;
    }

    pub fn delete(self: *FormData, name: []const u8) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].name, name)) {
                const removed = self.entries.orderedRemove(i);
                self.allocator.free(removed.name);
                self.allocator.free(removed.value);
            } else {
                i += 1;
            }
        }
    }

    pub fn set(self: *FormData, name: []const u8, value: []const u8) !void {
        var found = false;
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].name, name)) {
                if (!found) {
                    self.allocator.free(self.entries.items[i].value);
                    self.entries.items[i].value = try self.allocator.dupe(u8, value);
                    found = true;
                    i += 1;
                } else {
                    const removed = self.entries.orderedRemove(i);
                    self.allocator.free(removed.name);
                    self.allocator.free(removed.value);
                }
            } else {
                i += 1;
            }
        }

        if (!found) {
            try self.append(name, value);
        }
    }
};

test "formdata append get set delete lifecycle" {
    const allocator = std.testing.allocator;
    var form = FormData.init(allocator);
    defer form.deinit();

    try form.append("username", "davoth_user");
    try form.append("action", "login");

    try std.testing.expect(form.has("username"));
    try std.testing.expectEqualStrings("davoth_user", form.get("username").?);

    try form.set("username", "davoth_admin");
    try std.testing.expectEqualStrings("davoth_admin", form.get("username").?);

    form.delete("action");
    try std.testing.expect(!form.has("action"));
}
