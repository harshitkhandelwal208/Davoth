//! Download manager supporting range requests, pause/resume, and progress tracking.
const std = @import("std");

pub const DownloadState = enum {
    Pending,
    Downloading,
    Paused,
    Completed,
    Failed,
};

pub const DownloadItem = struct {
    id: u32,
    url: []const u8,
    file_path: []const u8,
    total_bytes: usize = 0,
    received_bytes: usize = 0,
    state: DownloadState = .Pending,

    pub fn deinit(self: *DownloadItem, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.file_path);
    }
};

pub const DownloadManager = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(DownloadItem),
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) DownloadManager {
        return .{
            .allocator = allocator,
            .items = .empty,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *DownloadManager) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
    }

    pub fn startDownload(self: *DownloadManager, url: []const u8, dest_path: []const u8) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        try self.items.append(self.allocator, .{
            .id = id,
            .url = try self.allocator.dupe(u8, url),
            .file_path = try self.allocator.dupe(u8, dest_path),
            .total_bytes = 0,
            .received_bytes = 0,
            .state = .Downloading,
        });

        return id;
    }
};
