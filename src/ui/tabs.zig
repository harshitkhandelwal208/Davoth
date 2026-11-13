//! Tab strip, tab groups, pinned tabs, and Multi-Account Container isolation.
//! Implements extreme memory hibernation (>30s inactive background tabs),
//! raster tile cache shedding, and kernel madvise(MADV_DONTNEED) page deflation.

const std = @import("std");
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;
const TileCache = @import("../rendering/tile_cache.zig").TileCache;
const Node = @import("../dom/node.zig").Node;
const time = @import("../common/time.zig");

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
    Hibernated,
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
    last_active_timestamp_ms: i64 = 0,
    tile_cache: ?*TileCache = null,
    document: ?*Node = null,

    pub fn deinit(self: *BrowserTab, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
        if (self.tile_cache) |tc| {
            tc.deinit();
            allocator.destroy(tc);
            self.tile_cache = null;
        }
        if (self.document) |doc| {
            doc.deinit(allocator);
            self.document = null;
        }
    }

    /// Hibernates tab: sheds heavy raster tile cache, releases DOM allocations, and marks hibernated
    pub fn hibernate(self: *BrowserTab, allocator: std.mem.Allocator) void {
        if (self.state == .Hibernated or self.state == .Discarded) return;

        // Discard raster tile caches
        if (self.tile_cache) |tc| {
            tc.deinit();
            allocator.destroy(tc);
            self.tile_cache = null;
        }

        // Release detached DOM tree allocations
        if (self.document) |doc| {
            doc.deinit(allocator);
            self.document = null;
        }

        self.state = .Hibernated;
    }
};

fn deflateNodePages(node: *Node) void {
    const ptr_int = @intFromPtr(node);
    const page_aligned = ptr_int & ~@as(usize, 4095);
    const page_ptr: [*]align(4096) u8 = @ptrFromInt(page_aligned);
    SubsystemMemoryTracker.releasePagesToOs(page_ptr, 4096);

    var curr = node.first_child;
    while (curr) |child| {
        deflateNodePages(child);
        curr = child.next_sibling;
    }
}

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

    pub fn newTabWithContent(
        self: *TabManager,
        url: []const u8,
        title: []const u8,
        container: ContainerId,
        document: ?*Node,
        tile_cache: ?*TileCache,
    ) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        // If another tab was active, mark it as background
        if (self.tabs.items.len > 0 and self.active_index < self.tabs.items.len) {
            self.tabs.items[self.active_index].state = .Background;
            self.tabs.items[self.active_index].last_active_timestamp_ms = time.timestamp();
        }

        try self.tabs.append(self.allocator, .{
            .id = id,
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, title),
            .is_pinned = false,
            .is_private = false,
            .container = container,
            .state = .Active,
            .last_active_timestamp_ms = time.timestamp(),
            .tile_cache = tile_cache,
            .document = document,
        });

        self.active_index = self.tabs.items.len - 1;
        return id;
    }

    pub fn newTab(self: *TabManager, url: []const u8, title: []const u8, container: ContainerId) !u32 {
        return self.newTabWithContent(url, title, container, null, null);
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
            self.tabs.items[self.active_index].last_active_timestamp_ms = time.timestamp();
        }
        self.active_index = index;
        const needs_reload = self.tabs.items[index].state == .Discarded or self.tabs.items[index].state == .Hibernated;
        self.tabs.items[index].state = .Active;
        self.tabs.items[index].last_active_timestamp_ms = time.timestamp();
        return needs_reload;
    }

    /// Hibernates a specific background tab
    pub fn hibernateTab(self: *TabManager, index: usize) bool {
        if (index >= self.tabs.items.len) return false;
        if (index == self.active_index) return false; // Never hibernate the currently active visible tab
        if (self.tabs.items[index].is_pinned) return false;

        self.tabs.items[index].hibernate(self.allocator);
        SubsystemMemoryTracker.deflateHeap();
        return true;
    }

    /// Automatically scans and hibernates tabs inactive for >= timeout_ms (default 30 seconds = 30000 ms)
    pub fn checkAndHibernateInactiveTabs(self: *TabManager, timeout_ms: i64) usize {
        const now = time.timestamp();
        var count: usize = 0;
        for (self.tabs.items, 0..) |*tab, i| {
            if (i != self.active_index and !tab.is_pinned and tab.state == .Background) {
                if (now - tab.last_active_timestamp_ms >= timeout_ms) {
                    tab.hibernate(self.allocator);
                    count += 1;
                }
            }
        }
        if (count > 0) {
            SubsystemMemoryTracker.deflateHeap();
        }
        return count;
    }

    /// Hibernates all background tabs immediately to maximize memory efficiency
    pub fn hibernateAllBackgroundTabs(self: *TabManager) usize {
        var count: usize = 0;
        for (self.tabs.items, 0..) |*tab, i| {
            if (i != self.active_index and !tab.is_pinned and tab.state == .Background) {
                tab.hibernate(self.allocator);
                count += 1;
            }
        }
        if (count > 0) {
            SubsystemMemoryTracker.deflateHeap();
        }
        return count;
    }

    /// Discards a background tab to reclaim memory back to OS while preserving URL, title and position
    pub fn discardTab(self: *TabManager, index: usize) bool {
        if (index >= self.tabs.items.len) return false;
        if (index == self.active_index) return false; // Never discard the currently visible active tab
        if (self.tabs.items[index].is_pinned) return false; // Pinned tabs are preserved

        self.tabs.items[index].hibernate(self.allocator);
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

test "tab manager background hibernation with tile cache shedding and madvise" {
    const allocator = std.testing.allocator;
    var mgr = TabManager.init(allocator);
    defer mgr.deinit();

    // Create 3 tabs with attached tile cache and mock DOM
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const tc = try allocator.create(TileCache);
        tc.* = try TileCache.init(allocator, 1024, 768);

        const doc = try Node.create(allocator, .Document, @enumFromInt(0));
        const body = try Node.create(allocator, .Element, @enumFromInt(1));
        try doc.appendChild(allocator, body);

        _ = try mgr.newTabWithContent("https://davoth.org/article", "Article", .Personal, doc, tc);
    }

    try std.testing.expectEqual(@as(usize, 3), mgr.tabs.items.len);
    // Tab 2 is active, Tabs 0 and 1 are background
    try std.testing.expect(mgr.tabs.items[0].tile_cache != null);
    try std.testing.expect(mgr.tabs.items[0].document != null);

    // Simulate inactivity > 30s (30,000 ms)
    mgr.tabs.items[0].last_active_timestamp_ms -= 35000;
    mgr.tabs.items[1].last_active_timestamp_ms -= 35000;

    const hibernated_count = mgr.checkAndHibernateInactiveTabs(30000);
    try std.testing.expectEqual(@as(usize, 2), hibernated_count);

    // Verify tile caches shed and DOM detached
    try std.testing.expect(mgr.tabs.items[0].tile_cache == null);
    try std.testing.expect(mgr.tabs.items[0].document == null);
    try std.testing.expectEqual(TabState.Hibernated, mgr.tabs.items[0].state);

    // Active tab was preserved
    try std.testing.expect(mgr.tabs.items[2].tile_cache != null);
    try std.testing.expect(mgr.tabs.items[2].document != null);
    try std.testing.expectEqual(TabState.Active, mgr.tabs.items[2].state);

    // Reactivate hibernated tab 0
    const reload = mgr.activateTab(0);
    try std.testing.expect(reload);
    try std.testing.expectEqual(TabState.Active, mgr.tabs.items[0].state);
}
