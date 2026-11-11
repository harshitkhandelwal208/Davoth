//! Tab strip, tab groups, pinned tabs, and Multi-Account Container isolation.
const std = @import("std");
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const ContainerId = enum(u8) {
    Default = 0,
    Personal = 1,
    Work = 2,
    Banking = 3,
    Shopping = 4,
};

pub const TabState = enum {
    Active,
    Background,
    Discarded,
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
    state: TabState = .Active,

    pub fn deinit(self: *BrowserTab, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
    }
};

pub const TabGroup = struct {
    name: []const u8,
    tab_ids: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !TabGroup {
        return .{
            .name = try allocator.dupe(u8, name),
            .tab_ids = .empty,
        };
    }

    pub fn deinit(self: *TabGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.tab_ids.deinit(allocator);
    }
};

pub const TabManager = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(BrowserTab),
    groups: std.ArrayList(TabGroup),
    active_index: usize = 0,
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) TabManager {
        return .{
            .allocator = allocator,
            .tabs = .empty,
            .groups = .empty,
            .active_index = 0,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *TabManager) void {
        for (self.tabs.items) |*tab| {
            tab.deinit(self.allocator);
        }
        self.tabs.deinit(self.allocator);
        for (self.groups.items) |*grp| {
            grp.deinit(self.allocator);
        }
        self.groups.deinit(self.allocator);
    }

    pub fn newTab(self: *TabManager, url: []const u8, title: []const u8, container: ContainerId) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        // If another tab was active, mark it as background
        if (self.tabs.items.len > 0 and self.active_index < self.tabs.items.len) {
            self.tabs.items[self.active_index].state = .Background;
        }

        try self.tabs.append(self.allocator, .{
            .id = id,
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, title),
            .is_pinned = false,
            .is_private = false,
            .container = container,
            .state = .Active,
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
            self.tabs.items[self.active_index].state = .Active;
        }
    }

    pub fn activeTab(self: *TabManager) ?*BrowserTab {
        if (self.active_index < self.tabs.items.len) {
            return &self.tabs.items[self.active_index];
        }
        return null;
    }

    pub fn activateTab(self: *TabManager, index: usize) bool {
        if (index >= self.tabs.items.len) return false;
        if (self.active_index < self.tabs.items.len) {
            self.tabs.items[self.active_index].state = .Background;
        }
        self.active_index = index;
        const needs_reload = self.tabs.items[index].state == .Discarded;
        self.tabs.items[index].state = .Active;
        return needs_reload;
    }

    /// Discards a background tab to reclaim memory back to OS while preserving URL, title and position
    pub fn discardTab(self: *TabManager, index: usize) bool {
        if (index >= self.tabs.items.len) return false;
        if (index == self.active_index) return false; // Never discard the currently visible active tab
        if (self.tabs.items[index].is_pinned) return false; // Pinned tabs are preserved

        self.tabs.items[index].state = .Discarded;
        return true;
    }

    /// Automatically discards the oldest unpinned background tab
    pub fn discardOldestBackgroundTab(self: *TabManager) bool {
        for (self.tabs.items, 0..) |tab, i| {
            if (i != self.active_index and !tab.is_pinned and tab.state == .Background) {
                return self.discardTab(i);
            }
        }
        return false;
    }
};

test "tab manager lifecycle, groups, and tab discard" {
    const allocator = std.testing.allocator;
    var mgr = TabManager.init(allocator);
    defer mgr.deinit();

    _ = try mgr.newTab("https://davoth.org", "Davoth", .Default);
    _ = try mgr.newTab("https://github.com", "GitHub", .Work);
    _ = try mgr.newTab("https://kernel.org", "Kernel", .Work);

    try std.testing.expectEqual(@as(usize, 3), mgr.tabs.items.len);
    try std.testing.expectEqual(@as(usize, 2), mgr.active_index);
    try std.testing.expectEqual(TabState.Active, mgr.activeTab().?.state);
    try std.testing.expectEqual(TabState.Background, mgr.tabs.items[0].state);

    // Discard background tab 0
    const discarded = mgr.discardTab(0);
    try std.testing.expect(discarded);
    try std.testing.expectEqual(TabState.Discarded, mgr.tabs.items[0].state);

    // Cannot discard active tab
    try std.testing.expect(!mgr.discardTab(2));

    // Switching to discarded tab reactivates it and signals needs_reload
    const needs_reload = mgr.activateTab(0);
    try std.testing.expect(needs_reload);
    try std.testing.expectEqual(TabState.Active, mgr.tabs.items[0].state);
}
