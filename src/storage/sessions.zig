//! Session restoration storage for open tabs and windows.
const std = @import("std");

pub const SavedTab = struct {
    url: []const u8,
    title: []const u8,
    is_pinned: bool = false,
    scroll_x: f32 = 0.0,
    scroll_y: f32 = 0.0,
};

pub const SavedSession = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(SavedTab),
    active_tab_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) SavedSession {
        return .{
            .allocator = allocator,
            .tabs = .empty,
            .active_tab_index = 0,
        };
    }

    pub fn deinit(self: *SavedSession) void {
        for (self.tabs.items) |tab| {
            self.allocator.free(tab.url);
            self.allocator.free(tab.title);
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn addTab(self: *SavedSession, url: []const u8, title: []const u8, pinned: bool) !void {
        try self.tabs.append(self.allocator, .{
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, title),
            .is_pinned = pinned,
        });
    }
};

test "session restore tabs" {
    const allocator = std.testing.allocator;
    var session = SavedSession.init(allocator);
    defer session.deinit();

    try session.addTab("https://davoth.org", "Davoth Browser", true);
    try std.testing.expectEqual(@as(usize, 1), session.tabs.items.len);
    try std.testing.expect(session.tabs.items[0].is_pinned);
}
