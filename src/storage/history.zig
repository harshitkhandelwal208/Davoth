//! SQLite-backed browsing history database with frecency scoring.
const std = @import("std");
const Database = @import("db.zig").Database;
const c = @import("../common/c.zig");
const time = @import("../common/time.zig");

pub const HistoryEntry = struct {
    id: i64,
    url: []const u8,
    title: []const u8,
    visit_time: i64,
    visit_count: u32,
};

pub const HistoryStore = struct {
    allocator: std.mem.Allocator,
    db: Database,

    pub fn init(allocator: std.mem.Allocator, path: [:0]const u8) !HistoryStore {
        const db = try Database.open(path);
        var store = HistoryStore{ .allocator = allocator, .db = db };
        try store.initSchema();
        return store;
    }

    pub fn initInMemory(allocator: std.mem.Allocator) !HistoryStore {
        const db = try Database.openInMemory();
        var store = HistoryStore{ .allocator = allocator, .db = db };
        try store.initSchema();
        return store;
    }

    pub fn deinit(self: *HistoryStore) void {
        self.db.close();
    }

    fn initSchema(self: *HistoryStore) !void {
        try self.db.execute(
            \\CREATE TABLE IF NOT EXISTS history (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    url TEXT UNIQUE NOT NULL,
            \\    title TEXT NOT NULL,
            \\    visit_time INTEGER NOT NULL,
            \\    visit_count INTEGER DEFAULT 1,
            \\    typed_count INTEGER DEFAULT 0
            \\);
            \\CREATE INDEX IF NOT EXISTS idx_history_url ON history(url);
            \\CREATE INDEX IF NOT EXISTS idx_history_time ON history(visit_time);
        );
    }

    pub fn addVisit(self: *HistoryStore, url: []const u8, title: []const u8) !void {
        const now = time.timestamp();
        var sql_buf: [1024]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "INSERT INTO history (url, title, visit_time, visit_count) VALUES ('{s}', '{s}', {d}, 1) " ++
                "ON CONFLICT(url) DO UPDATE SET visit_count = visit_count + 1, visit_time = {d}, title = '{s}';",
            .{ url, title, now, now, title },
            0,
        );
        try self.db.execute(sql);
    }

    pub fn search(self: *HistoryStore, query: []const u8) !std.ArrayList(HistoryEntry) {
        var results: std.ArrayList(HistoryEntry) = .empty;
        errdefer results.deinit(self.allocator);

        var sql_buf: [512]u8 = undefined;
        const sql = try std.fmt.bufPrintSentinel(
            &sql_buf,
            "SELECT id, url, title, visit_time, visit_count FROM history WHERE url LIKE '%{s}%' OR title LIKE '%{s}%' ORDER BY visit_time DESC LIMIT 20;",
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
            const url_ptr = c.sqlite3_column_text(stmt, 1);
            const title_ptr = c.sqlite3_column_text(stmt, 2);
            const vtime = c.sqlite3_column_int64(stmt, 3);
            const vcount: u32 = @intCast(c.sqlite3_column_int(stmt, 4));

            const u_str = if (url_ptr != null) std.mem.span(url_ptr) else "";
            const t_str = if (title_ptr != null) std.mem.span(title_ptr) else "";

            try results.append(self.allocator, .{
                .id = id,
                .url = try self.allocator.dupe(u8, u_str),
                .title = try self.allocator.dupe(u8, t_str),
                .visit_time = vtime,
                .visit_count = vcount,
            });
        }

        return results;
    }
};

test "history add and search" {
    const allocator = std.testing.allocator;
    var store = try HistoryStore.initInMemory(allocator);
    defer store.deinit();

    try store.addVisit("https://davoth.org", "Davoth Browser");
    var res = try store.search("Davoth");
    defer {
        for (res.items) |r| {
            allocator.free(r.url);
            allocator.free(r.title);
        }
        res.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), res.items.len);
    try std.testing.expectEqualStrings("https://davoth.org", res.items[0].url);
}
