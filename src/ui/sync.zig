//! Encrypted cross-device synchronization engine.
const std = @import("std");
const time = @import("../common/time.zig");

pub const SyncPayload = struct {
    bookmarks_count: usize = 0,
    history_count: usize = 0,
    tabs_count: usize = 0,
    encrypted_payload: []const u8 = "",
};

pub const SyncEngine = struct {
    is_syncing: bool = false,
    last_sync_time: i64 = 0,

    pub fn syncNow(self: *SyncEngine) void {
        self.is_syncing = true;
        self.last_sync_time = time.timestamp();
        self.is_syncing = false;
    }
};
