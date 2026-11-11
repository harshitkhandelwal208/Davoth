//! Automated upstream AdNauseam update detection and regression testing tool.
const std = @import("std");
const HttpClient = @import("../../net/http1.zig").HttpClient;
const Manifest = @import("../../extensions/manifest.zig").Manifest;

pub const AdNauseamUpdater = struct {
    allocator: std.mem.Allocator,
    current_version: []const u8 = "3.29.2",

    pub fn init(allocator: std.mem.Allocator) AdNauseamUpdater {
        return .{
            .allocator = allocator,
            .current_version = "3.29.2",
        };
    }

    pub fn checkForUpdates(self: *AdNauseamUpdater) !bool {
        // Query GitHub API for latest release
        var client = HttpClient.init(self.allocator);
        defer client.deinit();

        const url = "https://api.github.com/repos/dhowe/AdNauseam/releases/latest";
        var resp = client.get(url) catch |err| {
            std.debug.print("AdNauseam update check offline: {}\n", .{err});
            return false;
        };
        defer resp.deinit();

        if (std.mem.indexOf(u8, resp.body, "\"tag_name\":")) |idx| {
            const start = idx + 12;
            const end = std.mem.indexOfPos(u8, resp.body, start, "\"") orelse return false;
            const latest_tag = resp.body[start..end];
            std.debug.print("Installed AdNauseam: v{s} | Upstream latest: {s}\n", .{ self.current_version, latest_tag });
            return !std.mem.endsWith(u8, latest_tag, self.current_version);
        }
        return false;
    }
};

test "adnauseam updater init" {
    const allocator = std.testing.allocator;
    const updater = AdNauseamUpdater.init(allocator);
    try std.testing.expectEqualStrings("3.29.2", updater.current_version);
}
