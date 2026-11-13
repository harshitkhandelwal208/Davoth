//! Session restoration storage for open tabs and windows.
//! Supports crash detection, container partition preservation, and JSON persistence.

const std = @import("std");
const ContainerId = @import("../common/types.zig").ContainerId;

pub const SavedTab = struct {
    url: []const u8,
    title: []const u8,
    container: ContainerId = .Default,
    is_pinned: bool = false,
    scroll_x: f32 = 0.0,
    scroll_y: f32 = 0.0,
    is_selected: bool = true,
};

pub const SavedSession = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(SavedTab),
    active_tab_index: usize = 0,
    was_crashed: bool = false,
    timestamp: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) SavedSession {
        return .{
            .allocator = allocator,
            .tabs = .empty,
            .active_tab_index = 0,
            .was_crashed = false,
            .timestamp = 0,
        };
    }

    pub fn deinit(self: *SavedSession) void {
        for (self.tabs.items) |tab| {
            self.allocator.free(tab.url);
            self.allocator.free(tab.title);
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn addTab(
        self: *SavedSession,
        url: []const u8,
        title: []const u8,
        container: ContainerId,
        pinned: bool,
    ) !void {
        try self.tabs.append(self.allocator, .{
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, title),
            .container = container,
            .is_pinned = pinned,
            .is_selected = true,
        });
    }

    pub fn serialize(self: *const SavedSession, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n  \"crashed\": ");
        if (self.was_crashed) {
            try buf.appendSlice(allocator, "true,\n");
        } else {
            try buf.appendSlice(allocator, "false,\n");
        }

        const idx_str = try std.fmt.allocPrint(allocator, "  \"active_tab\": {d},\n  \"tabs\": [\n", .{self.active_tab_index});
        defer allocator.free(idx_str);
        try buf.appendSlice(allocator, idx_str);

        for (self.tabs.items, 0..) |tab, i| {
            const comma = if (i + 1 < self.tabs.items.len) "," else "";
            const entry = try std.fmt.allocPrint(
                allocator,
                \\    {{ "url": "{s}", "title": "{s}", "container": {d}, "pinned": {s} }}{s}
                \\
            ,
                .{
                    tab.url,
                    tab.title,
                    @intFromEnum(tab.container),
                    if (tab.is_pinned) "true" else "false",
                    comma,
                },
            );
            defer allocator.free(entry);
            try buf.appendSlice(allocator, entry);
        }

        try buf.appendSlice(allocator, "  ]\n}\n");
        return try buf.toOwnedSlice(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, json_data: []const u8) !SavedSession {
        var session = SavedSession.init(allocator);
        errdefer session.deinit();

        if (std.mem.indexOf(u8, json_data, "\"crashed\": true")) |_| {
            session.was_crashed = true;
        }

        // Parse tabs array
        var idx: usize = 0;
        while (std.mem.indexOfPos(u8, json_data, idx, "\"url\": \"")) |u_pos| {
            const u_start = u_pos + 8;
            const u_end = std.mem.indexOfPos(u8, json_data, u_start, "\"") orelse break;
            const url = json_data[u_start..u_end];

            var title: []const u8 = "New Tab";
            if (std.mem.indexOfPos(u8, json_data, u_end, "\"title\": \"")) |t_pos| {
                const t_start = t_pos + 10;
                if (std.mem.indexOfPos(u8, json_data, t_start, "\"")) |t_end| {
                    title = json_data[t_start..t_end];
                }
            }

            var container: ContainerId = .Default;
            if (std.mem.indexOfPos(u8, json_data, u_end, "\"container\": ")) |c_pos| {
                const c_val = json_data[c_pos + 13];
                if (c_val >= '0' and c_val <= '4') {
                    container = @enumFromInt(c_val - '0');
                }
            }

            var pinned: bool = false;
            if (std.mem.indexOfPos(u8, json_data, u_end, "\"pinned\": true")) |p_pos| {
                if (p_pos < u_end + 120) pinned = true;
            }

            try session.addTab(url, title, container, pinned);
            idx = u_end + 1;
        }

        return session;
    }
};

test "session restore tabs and json serialization" {
    const allocator = std.testing.allocator;
    var session = SavedSession.init(allocator);
    defer session.deinit();

    try session.addTab("https://davoth.org", "Davoth Browser", .Default, true);
    try session.addTab("https://work.internal", "Corporate Portal", .Work, false);
    session.was_crashed = true;

    try std.testing.expectEqual(@as(usize, 2), session.tabs.items.len);
    try std.testing.expect(session.tabs.items[0].is_pinned);
    try std.testing.expectEqual(ContainerId.Work, session.tabs.items[1].container);

    const json = try session.serialize(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"crashed\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Corporate Portal") != null);

    // Test deserialization
    var loaded = try SavedSession.deserialize(allocator, json);
    defer loaded.deinit();

    try std.testing.expect(loaded.was_crashed);
    try std.testing.expectEqual(@as(usize, 2), loaded.tabs.items.len);
    try std.testing.expectEqualStrings("Davoth Browser", loaded.tabs.items[0].title);
    try std.testing.expectEqual(ContainerId.Work, loaded.tabs.items[1].container);
    try std.testing.expect(loaded.tabs.items[0].is_pinned);
}
