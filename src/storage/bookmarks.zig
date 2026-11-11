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

    pub fn deinit(self: *BookmarkItem, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.url);
    }
};

pub const BookmarkStore = struct {
    allocator: std.mem.Allocator,
    db: Database,

    pub fn init(allocator: std.mem.Allocator, path: [:0]const u8) !BookmarkStore {
        const db = try Database.open(path);
        var store = BookmarkStore{ .allocator = allocator, .db = db };
        try store.initSchema();
        return store;
    }

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

    pub fn addFolder(self: *BookmarkStore, parent_id: i64, title: []const u8) !void {
        const now = time.timestamp();
        var sql_buf: [512]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "INSERT INTO bookmarks (parent_id, is_folder, title, url, date_added) VALUES ({d}, 1, '{s}', '', {d});",
            .{ parent_id, title, now },
            0,
        );
        try self.db.execute(sql);
    }

    pub fn getBookmarksInFolder(self: *BookmarkStore, parent_id: i64) !std.ArrayList(BookmarkItem) {
        var results: std.ArrayList(BookmarkItem) = .empty;
        errdefer {
            for (results.items) |*b| b.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        var sql_buf: [256]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "SELECT id, parent_id, is_folder, title, url FROM bookmarks WHERE parent_id = {d} ORDER BY id ASC;",
            .{parent_id},
            0,
        );

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db.handle, sql, -1, &stmt, null) != c.SQLITE_OK) {
            return results;
        }
        defer _ = c.sqlite3_finalize(stmt);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const id = c.sqlite3_column_int64(stmt, 0);
            const p_id = c.sqlite3_column_int64(stmt, 1);
            const is_folder = c.sqlite3_column_int(stmt, 2) != 0;
            const title_ptr = c.sqlite3_column_text(stmt, 3);
            const url_ptr = c.sqlite3_column_text(stmt, 4);

            const t_str = if (title_ptr != null) std.mem.span(title_ptr) else "";
            const u_str = if (url_ptr != null) std.mem.span(url_ptr) else "";

            try results.append(self.allocator, .{
                .id = id,
                .parent_id = p_id,
                .is_folder = is_folder,
                .title = try self.allocator.dupe(u8, t_str),
                .url = try self.allocator.dupe(u8, u_str),
            });
        }

        return results;
    }

    pub fn searchBookmarks(self: *BookmarkStore, query: []const u8) !std.ArrayList(BookmarkItem) {
        var results: std.ArrayList(BookmarkItem) = .empty;
        errdefer {
            for (results.items) |*b| b.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        var sql_buf: [512]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "SELECT id, parent_id, is_folder, title, url FROM bookmarks WHERE is_folder = 0 AND (title LIKE '%{s}%' OR url LIKE '%{s}%') ORDER BY id DESC LIMIT 50;",
            .{ query, query },
            0,
        );

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db.handle, sql, -1, &stmt, null) != c.SQLITE_OK) {
            return results;
        }
        defer _ = c.sqlite3_finalize(stmt);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const id = c.sqlite3_column_int64(stmt, 0);
            const p_id = c.sqlite3_column_int64(stmt, 1);
            const is_folder = c.sqlite3_column_int(stmt, 2) != 0;
            const title_ptr = c.sqlite3_column_text(stmt, 3);
            const url_ptr = c.sqlite3_column_text(stmt, 4);

            const t_str = if (title_ptr != null) std.mem.span(title_ptr) else "";
            const u_str = if (url_ptr != null) std.mem.span(url_ptr) else "";

            try results.append(self.allocator, .{
                .id = id,
                .parent_id = p_id,
                .is_folder = is_folder,
                .title = try self.allocator.dupe(u8, t_str),
                .url = try self.allocator.dupe(u8, u_str),
            });
        }

        return results;
    }

    pub fn removeBookmark(self: *BookmarkStore, id: i64) !void {
        var sql_buf: [128]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "DELETE FROM bookmarks WHERE id = {d};",
            .{id},
            0,
        );
        try self.db.execute(sql);
    }
};

test "bookmarks store add, query, and search" {
    const allocator = std.testing.allocator;
    var store = try BookmarkStore.initInMemory(allocator);
    defer store.deinit();

    try store.addBookmark(1, "Davoth Project", "https://github.com/davoth/browser");
    try store.addBookmark(1, "Zig Language", "https://ziglang.org");
    try store.addFolder(1, "Development");

    var folder_items = try store.getBookmarksInFolder(1);
    defer {
        for (folder_items.items) |*b| b.deinit(allocator);
        folder_items.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), folder_items.items.len);

    var search_results = try store.searchBookmarks("Davoth");
    defer {
        for (search_results.items) |*b| b.deinit(allocator);
        search_results.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), search_results.items.len);
    try std.testing.expectEqualStrings("Davoth Project", search_results.items[0].title);
}
