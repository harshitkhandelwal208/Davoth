//! Firefox-style Downloads Panel, Drawer, and `about:downloads` UI renderer.
const std = @import("std");
const DownloadManager = @import("../net/downloads.zig").DownloadManager;
const DownloadItem = @import("../net/downloads.zig").DownloadItem;
const DownloadState = @import("../net/downloads.zig").DownloadState;

pub const DownloadsPanel = struct {
    allocator: std.mem.Allocator,
    manager: *DownloadManager,
    is_open: bool = false,

    pub fn init(allocator: std.mem.Allocator, manager: *DownloadManager) DownloadsPanel {
        return .{
            .allocator = allocator,
            .manager = manager,
            .is_open = false,
        };
    }

    pub fn togglePanel(self: *DownloadsPanel) void {
        self.is_open = !self.is_open;
    }

    /// Formats raw byte counts into human-readable strings (e.g., "12.4 MB", "550 KB")
    pub fn formatBytes(allocator: std.mem.Allocator, bytes: usize) ![]u8 {
        const f_bytes: f64 = @floatFromInt(bytes);
        if (bytes >= 1024 * 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.2} GB", .{f_bytes / (1024.0 * 1024.0 * 1024.0)});
        } else if (bytes >= 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} MB", .{f_bytes / (1024.0 * 1024.0)});
        } else if (bytes >= 1024) {
            return std.fmt.allocPrint(allocator, "{d:.0} KB", .{f_bytes / 1024.0});
        }
        return std.fmt.allocPrint(allocator, "{d} B", .{bytes});
    }

    /// Formats transfer rate (e.g., "2.4 MB/s")
    pub fn formatSpeed(allocator: std.mem.Allocator, speed_bps: f64) ![]u8 {
        if (speed_bps >= 1024.0 * 1024.0) {
            return std.fmt.allocPrint(allocator, "{d:.1} MB/s", .{speed_bps / (1024.0 * 1024.0)});
        } else if (speed_bps >= 1024.0) {
            return std.fmt.allocPrint(allocator, "{d:.0} KB/s", .{speed_bps / 1024.0});
        }
        return std.fmt.allocPrint(allocator, "{d:.0} B/s", .{speed_bps});
    }

    /// Formats remaining download time (e.g., "01:45 remaining")
    pub fn formatEta(allocator: std.mem.Allocator, item: *const DownloadItem) ![]u8 {
        switch (item.state) {
            .Completed => return allocator.dupe(u8, "Completed"),
            .Paused => return allocator.dupe(u8, "Paused"),
            .Canceled => return allocator.dupe(u8, "Canceled"),
            .Failed => return allocator.dupe(u8, "Failed"),
            .Pending => return allocator.dupe(u8, "Starting..."),
            .Downloading => {
                if (item.etaSeconds()) |eta| {
                    const mins = eta / 60;
                    const secs = eta % 60;
                    return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2} remaining", .{ mins, secs });
                }
                return allocator.dupe(u8, "Calculating...");
            },
        }
    }

    /// Generates HTML markup for rendering `about:downloads` internal page
    pub fn renderAboutDownloadsHtml(self: *DownloadsPanel) ![]u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <title>Downloads — Davoth</title>
            \\  <style>
            \\    body { background-color: #1e1e2e; color: #cdd6f4; font-family: sans-serif; padding: 24px; }
            \\    .download-card { background: #313244; border-radius: 8px; padding: 16px; margin-bottom: 12px; }
            \\    .filename { font-size: 16px; font-weight: bold; color: #89b4fa; }
            \\    .meta { font-size: 13px; color: #a6adc8; margin-top: 4px; }
            \\    .progress-bar { background: #45475a; height: 8px; border-radius: 4px; overflow: hidden; margin-top: 8px; }
            \\    .progress-fill { background: #a6e3a1; height: 100%; }
            \\  </style>
            \\</head>
            \\<body>
            \\  <h1>Downloads</h1>
        );

        if (self.manager.items.items.len == 0) {
            try buf.appendSlice(self.allocator, "<p>No active or past downloads.</p>");
        } else {
            for (self.manager.items.items) |item| {
                const rec_str = try formatBytes(self.allocator, item.received_bytes);
                defer self.allocator.free(rec_str);

                const tot_str = try formatBytes(self.allocator, item.total_bytes);
                defer self.allocator.free(tot_str);

                const eta_str = try formatEta(self.allocator, &item);
                defer self.allocator.free(eta_str);

                const speed_str = try formatSpeed(self.allocator, item.speed_bps);
                defer self.allocator.free(speed_str);

                const pct = item.progressPercent();

                const row = try std.fmt.allocPrint(self.allocator,
                    \\  <div class="download-card">
                    \\    <div class="filename">{s}</div>
                    \\    <div class="meta">{s} of {s} — {s} ({s})</div>
                    \\    <div class="progress-bar"><div class="progress-fill" style="width: {d:.1}%;"></div></div>
                    \\  </div>
                ,
                    .{ item.file_path, rec_str, tot_str, speed_str, eta_str, pct },
                );
                defer self.allocator.free(row);
                try buf.appendSlice(self.allocator, row);
            }
        }

        try buf.appendSlice(self.allocator, "</body></html>");
        return buf.toOwnedSlice(self.allocator);
    }
};

test "downloads panel byte, speed and eta formatting" {
    const allocator = std.testing.allocator;

    const b1 = try DownloadsPanel.formatBytes(allocator, 15_400_000);
    defer allocator.free(b1);
    try std.testing.expectEqualStrings("14.7 MB", b1);

    const s1 = try DownloadsPanel.formatSpeed(allocator, 2_500_000);
    defer allocator.free(s1);
    try std.testing.expectEqualStrings("2.4 MB/s", s1);

    var item = DownloadItem{
        .id = 1,
        .url = try allocator.dupe(u8, "https://example.com/file.zip"),
        .file_path = try allocator.dupe(u8, "file.zip"),
        .mime_type = try allocator.dupe(u8, "application/zip"),
        .total_bytes = 10_000_000,
        .received_bytes = 5_000_000,
        .speed_bps = 1_000_000.0,
        .state = .Downloading,
    };
    defer item.deinit(allocator);

    const eta = try DownloadsPanel.formatEta(allocator, &item);
    defer allocator.free(eta);
    try std.testing.expectEqualStrings("00:05 remaining", eta);
}

test "downloads panel about:downloads html generation" {
    const allocator = std.testing.allocator;
    var mgr = try DownloadManager.init(allocator, null);
    defer mgr.deinit();

    _ = try mgr.startDownload("https://davoth.org/bundle.tar.gz", "/tmp/bundle.tar.gz", "application/gzip");

    var panel = DownloadsPanel.init(allocator, &mgr);
    const html = try panel.renderAboutDownloadsHtml();
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "bundle.tar.gz") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Downloads — Davoth") != null);
}
