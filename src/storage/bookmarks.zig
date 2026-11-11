//! SQLite-backed hierarchical bookmarks database.
const std = @import("std");
const Database = @import("db.zig").Database;
const c = @import("../common/c.zig");
const time = @import("../common/time.zig");

pub const BookmarkItem = struct {
    id: i64,
    parent_id: i64,
    is_folder: bool,
    title: []const u8,
    url: []const u8,
};

pub const BookmarkStore = struct {
    allocator: std.mem.Allocator,
    db: Database,

    pub fn initInMemory(allocator: std.mem.Allocator) !BookmarkStore {
        const db = try Database.openInMemory();
        var store = BookmarkStore{ .allocator = allocator, .db = db };
        try store.initSchema();
        return store;
    }

    pub fn deinit(self: *BookmarkStore) void {
        self.db.close();
    }

    fn initSchema(self: *BookmarkStore) !void {
        try self.db.execute(
            \\CREATE TABLE IF NOT EXISTS bookmarks (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    parent_id INTEGER DEFAULT 0,
            \\    is_folder INTEGER DEFAULT 0,
            \\    title TEXT NOT NULL,
            \\    url TEXT DEFAULT '',
            \\    date_added INTEGER NOT NULL
            \\);
            \\INSERT INTO bookmarks (id, parent_id, is_folder, title, url, date_added) VALUES
            \\(1, 0, 1, 'Bookmarks Toolbar', '', 0),
            \\(2, 0, 1, 'Bookmarks Menu', '', 0),
            \\(3, 0, 1, 'Other Bookmarks', '', 0);
        );
    }

    pub fn addBookmark(self: *BookmarkStore, parent_id: i64, title: []const u8, url: []const u8) !void {
        const now = time.timestamp();
        var sql_buf: [1024]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "INSERT INTO bookmarks (parent_id, is_folder, title, url, date_added) VALUES ({d}, 0, '{s}', '{s}', {d});",
            .{ parent_id, title, url, now },
            0,
        );
        try self.db.execute(sql);
    }
};

test "bookmarks store add" {
    const allocator = std.testing.allocator;
    var store = try BookmarkStore.initInMemory(allocator);
    defer store.deinit();

    try store.addBookmark(1, "Davoth Project", "https://github.com/davoth/browser");
}
