//! browser.tabs API implementation.
const std = @import("std");

pub const ExtensionTab = struct {
    id: u32,
    index: u32,
    window_id: u32,
    url: []const u8,
    title: []const u8,
    active: bool = false,
    pinned: bool = false,
};

pub const TabsApi = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayList(ExtensionTab),
    next_tab_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) TabsApi {
        return .{
            .allocator = allocator,
            .tabs = .empty,
            .next_tab_id = 1,
        };
    }

    pub fn deinit(self: *TabsApi) void {
        for (self.tabs.items) |tab| {
            self.allocator.free(tab.url);
            self.allocator.free(tab.title);
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn create(self: *TabsApi, url: []const u8) !u32 {
        const id = self.next_tab_id;
        self.next_tab_id += 1;

        try self.tabs.append(self.allocator, .{
            .id = id,
            .index = @truncate(self.tabs.items.len),
            .window_id = 1,
            .url = try self.allocator.dupe(u8, url),
            .title = try self.allocator.dupe(u8, "New Tab"),
            .active = true,
            .pinned = false,
        });

        return id;
    }

    pub fn remove(self: *TabsApi, tab_id: u32) void {
        var i: usize = 0;
        while (i < self.tabs.items.len) {
            if (self.tabs.items[i].id == tab_id) {
                const removed = self.tabs.orderedRemove(i);
                self.allocator.free(removed.url);
                self.allocator.free(removed.title);
                return;
            }
            i += 1;
        }
    }
};

test "tabs api create and remove" {
    const allocator = std.testing.allocator;
    var api = TabsApi.init(allocator);
    defer api.deinit();

    const id = try api.create("https://davoth.org");
    try std.testing.expectEqual(@as(usize, 1), api.tabs.items.len);
    api.remove(id);
    try std.testing.expectEqual(@as(usize, 0), api.tabs.items.len);
}
