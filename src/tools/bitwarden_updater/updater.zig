//! Automated upstream Bitwarden update detection and integration tool.
const std = @import("std");
const HttpClient = @import("../../net/http1.zig").HttpClient;

pub const BitwardenUpdater = struct {
    allocator: std.mem.Allocator,
    current_version: []const u8 = "2026.10.2",

    pub fn init(allocator: std.mem.Allocator) BitwardenUpdater {
        return .{
            .allocator = allocator,
            .current_version = "2026.10.2",
        };
    }

    pub fn checkForUpdates(self: *BitwardenUpdater) !bool {
        var client = HttpClient.init(self.allocator);
        defer client.deinit();

        const url = "https://api.github.com/repos/bitwarden/clients/releases?per_page=5";
        var resp = client.get(url) catch |err| {
            std.debug.print("Bitwarden update check offline: {}\n", .{err});
            return false;
        };
        defer resp.deinit();

        if (std.mem.indexOf(u8, resp.body, "\"tag_name\": \"browser-v")) |idx| {
            const start = idx + 22;
            const end = std.mem.indexOfPos(u8, resp.body, start, "\"") orelse return false;
            const latest_tag = resp.body[start..end];
            std.debug.print("Installed Bitwarden: v{s} | Upstream latest: {s}\n", .{ self.current_version, latest_tag });
            return !std.mem.eql(u8, latest_tag, self.current_version);
        }
        return false;
    }
};

test "bitwarden updater init" {
    const allocator = std.testing.allocator;
    const updater = BitwardenUpdater.init(allocator);
    try std.testing.expectEqualStrings("2026.10.2", updater.current_version);
}
