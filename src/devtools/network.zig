//! Network traffic inspector and waterfall logger.
const std = @import("std");

pub const NetworkLogEntry = struct {
    url: []const u8,
    method: []const u8,
    status: u16,
    size_bytes: usize,
    duration_ms: u64,
};

pub const NetworkInspector = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(NetworkLogEntry),

    pub fn init(allocator: std.mem.Allocator) NetworkInspector {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *NetworkInspector) void {
        for (self.entries.items) |e| {
            self.allocator.free(e.url);
            self.allocator.free(e.method);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn logRequest(self: *NetworkInspector, url: []const u8, method: []const u8, status: u16, size: usize, duration: u64) !void {
        try self.entries.append(self.allocator, .{
            .url = try self.allocator.dupe(u8, url),
            .method = try self.allocator.dupe(u8, method),
            .status = status,
            .size_bytes = size,
            .duration_ms = duration,
        });
    }
};
