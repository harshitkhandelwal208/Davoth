//! SQLite3 persistent database engine wrapper.
const std = @import("std");
const c = @import("../common/c.zig");

pub const Database = struct {
    handle: ?*c.sqlite3,

    pub fn open(path: [:0]const u8) !Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return error.SqliteOpenFailed;
        }
        return Database{ .handle = db };
    }

    pub fn openInMemory() !Database {
        return open(":memory:");
    }

    pub fn close(self: *Database) void {
        if (self.handle) |db| {
            _ = c.sqlite3_close(db);
            self.handle = null;
        }
    }

    pub fn execute(self: *Database, sql: [:0]const u8) !void {
        const db = self.handle orelse return error.DatabaseNotOpen;
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(db, sql, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg != null) c.sqlite3_free(err_msg);
            return error.SqliteExecFailed;
        }
    }
};

test "sqlite database in memory" {
    var db = try Database.openInMemory();
    defer db.close();

    try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);");
    try db.execute("INSERT INTO test (name) VALUES ('Davoth');");
}
