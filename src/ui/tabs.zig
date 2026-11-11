//! Tab strip, tab groups, pinned tabs, and Multi-Account Container isolation.
const std = @import("std");

pub const ContainerId = enum(u8) {
    Default = 0,
    Personal = 1,
    Work = 2,
    Banking = 3,
    Shopping = 4,
};

pub const BrowserTab = struct {
    id: u32,
    url: []const u8,
    title: []const u8,
    is_pinned: bool = false,
    is_private: bool = false,
    container: ContainerId = .Default,
    scroll_y: f32 = 0.0,
    zoom_level: f32 = 1.0,

    pub fn deinit(self: *BrowserTab, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
    }
};

pub const TabGroup = struct {
    name: []const u8,
    tab_ids: std.ArrayList(u32),
};

pub const TabManager = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(BrowserTab),
    active_index: usize = 0,
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) TabManager {
        return .{
            .allocator = allocator,
            .tabs = .empty,
            .active_index = 0,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *TabManager) void {
        for (self.tabs.items) |*tab| {
            tab.deinit(self.allocator);
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn newTab(self: *TabManager, url: []const u8, title: []const u8, container: ContainerId) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        try self.tabs.append(self.allocator, .{
            .id = id,
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, title),
            .is_pinned = false,
            .is_private = false,
            .container = container,
        });

        self.active_index = self.tabs.items.len - 1;
        return id;
    }

    pub fn closeTab(self: *TabManager, index: usize) void {
        if (index >= self.tabs.items.len) return;
        var tab = self.tabs.orderedRemove(index);
        tab.deinit(self.allocator);
        if (self.active_index >= self.tabs.items.len and self.tabs.items.len > 0) {
            self.active_index = self.tabs.items.len - 1;
        }
    }

    pub fn activeTab(self: *TabManager) ?*BrowserTab {
        if (self.active_index < self.tabs.items.len) {
            return &self.tabs.items[self.active_index];
        }
        return null;
    }
};

test "tab manager new tab and close" {
    const allocator = std.testing.allocator;
    var mgr = TabManager.init(allocator);
    defer mgr.deinit();

    _ = try mgr.newTab("https://davoth.org", "Davoth", .Default);
    _ = try mgr.newTab("https://github.com", "GitHub", .Work);

    try std.testing.expectEqual(@as(usize, 2), mgr.tabs.items.len);
    try std.testing.expectEqual(ContainerId.Work, mgr.activeTab().?.container);

    mgr.closeTab(1);
    try std.testing.expectEqual(@as(usize, 1), mgr.tabs.items.len);
}
