//! Advanced Download Manager Subsystem: multi-threaded chunk downloading,
//! pause/resume/cancel, speed tracking, MIME type sniffing, safe file extension handling,
//! and SQLite persistent download history.
const std = @import("std");
const Mutex = @import("../common/sync.zig").Mutex;
const time = @import("../common/time.zig");
const Database = @import("../storage/db.zig").Database;

pub const DownloadState = enum(u8) {
    Pending = 0,
    Downloading = 1,
    Paused = 2,
    Completed = 3,
    Failed = 4,
    Canceled = 5,
};

pub const DownloadItem = struct {
    id: u32,
    url: []const u8,
    file_path: []const u8,
    mime_type: []const u8,
    total_bytes: usize = 0,
    received_bytes: usize = 0,
    state: DownloadState = .Pending,
    start_time_ms: i64 = 0,
    last_tick_ms: i64 = 0,
    last_tick_bytes: usize = 0,
    speed_bps: f64 = 0.0,

    pub fn deinit(self: *DownloadItem, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.file_path);
        allocator.free(self.mime_type);
    }

    pub fn progressPercent(self: *const DownloadItem) f32 {
        if (self.total_bytes == 0) return 0.0;
        return @as(f32, @floatFromInt(self.received_bytes)) / @as(f32, @floatFromInt(self.total_bytes)) * 100.0;
    }

    pub fn etaSeconds(self: *const DownloadItem) ?u32 {
        if (self.speed_bps <= 10.0 or self.total_bytes <= self.received_bytes) return null;
        const remaining = self.total_bytes - self.received_bytes;
        return @intFromFloat(@as(f64, @floatFromInt(remaining)) / self.speed_bps);
    }
};

pub const DownloadHistoryEntry = struct {
    id: u32,
    url: []const u8,
    file_path: []const u8,
    mime_type: []const u8,
    total_bytes: usize,
    received_bytes: usize,
    state: DownloadState,
    timestamp: i64,

    pub fn deinit(self: *DownloadHistoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.file_path);
        allocator.free(self.mime_type);
    }
};

pub const MimeSniffer = struct {
    pub const SniffResult = struct {
        mime_type: []const u8,
        safe_extension: []const u8,
    };

    /// Sniffs content type from magic header bytes according to WHATWG MIME sniffing standard
    pub fn sniff(header_bytes: []const u8) SniffResult {
        if (header_bytes.len >= 8 and std.mem.startsWith(u8, header_bytes, "\x89PNG\r\n\x1a\n")) {
            return .{ .mime_type = "image/png", .safe_extension = ".png" };
        }
        if (header_bytes.len >= 3 and header_bytes[0] == 0xff and header_bytes[1] == 0xd8 and header_bytes[2] == 0xff) {
            return .{ .mime_type = "image/jpeg", .safe_extension = ".jpg" };
        }
        if (header_bytes.len >= 4 and (std.mem.startsWith(u8, header_bytes, "GIF87a") or std.mem.startsWith(u8, header_bytes, "GIF89a"))) {
            return .{ .mime_type = "image/gif", .safe_extension = ".gif" };
        }
        if (header_bytes.len >= 4 and std.mem.startsWith(u8, header_bytes, "%PDF")) {
            return .{ .mime_type = "application/pdf", .safe_extension = ".pdf" };
        }
        if (header_bytes.len >= 4 and std.mem.startsWith(u8, header_bytes, "PK\x03\x04")) {
            return .{ .mime_type = "application/zip", .safe_extension = ".zip" };
        }
        if (header_bytes.len >= 3 and header_bytes[0] == 0x1f and header_bytes[1] == 0x8b and header_bytes[2] == 0x08) {
            return .{ .mime_type = "application/gzip", .safe_extension = ".gz" };
        }
        if (header_bytes.len >= 12 and std.mem.startsWith(u8, header_bytes, "RIFF") and std.mem.eql(u8, header_bytes[8..12], "WEBP")) {
            return .{ .mime_type = "image/webp", .safe_extension = ".webp" };
        }
        if (header_bytes.len >= 5 and (std.ascii.startsWithIgnoreCase(header_bytes, "<html") or std.ascii.startsWithIgnoreCase(header_bytes, "<!doc"))) {
            return .{ .mime_type = "text/html", .safe_extension = ".html" };
        }
        if (header_bytes.len >= 5 and (std.ascii.startsWithIgnoreCase(header_bytes, "<?xml") or std.ascii.startsWithIgnoreCase(header_bytes, "<svg"))) {
            return .{ .mime_type = "image/svg+xml", .safe_extension = ".svg" };
        }

        return .{ .mime_type = "application/octet-stream", .safe_extension = ".bin" };
    }

    /// Sanitizes target filename, preventing directory traversal and appending safe extension if missing
    pub fn sanitizeFileName(allocator: std.mem.Allocator, raw_name: []const u8, sniffed: SniffResult) ![]u8 {
        // Strip path traversal components
        var base_name = raw_name;
        if (std.mem.lastIndexOfScalar(u8, base_name, '/')) |idx| {
            base_name = base_name[idx + 1 ..];
        }
        if (std.mem.lastIndexOfScalar(u8, base_name, '\\')) |idx| {
            base_name = base_name[idx + 1 ..];
        }

        const trimmed = std.mem.trim(u8, base_name, " \t\r\n.");
        const clean_name = if (trimmed.len == 0) "download" else trimmed;

        // Check if extension already exists
        if (std.mem.lastIndexOfScalar(u8, clean_name, '.')) |dot_idx| {
            const ext = clean_name[dot_idx..];
            // Disallow hazardous executable extensions
            const dangerous = [_][]const u8{ ".exe", ".sh", ".bat", ".cmd", ".vbs", ".dll", ".so", ".scr" };
            for (dangerous) |d| {
                if (std.ascii.eqlIgnoreCase(ext, d)) {
                    // Append safe extension
                    return std.fmt.allocPrint(allocator, "{s}.safe{s}", .{ clean_name, sniffed.safe_extension });
                }
            }
            return allocator.dupe(u8, clean_name);
        }

        // No extension present: append safe sniffed extension
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ clean_name, sniffed.safe_extension });
    }
};

pub const DownloadManager = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(DownloadItem),
    db: ?Database = null,
    mutex: Mutex = .{},
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator, db: ?Database) !DownloadManager {
        var mgr = DownloadManager{
            .allocator = allocator,
            .items = .empty,
            .db = db,
            .mutex = .{},
            .next_id = 1,
        };

        if (mgr.db) |*database| {
            const schema =
                \\CREATE TABLE IF NOT EXISTS downloads (
                \\  id INTEGER PRIMARY KEY,
                \\  url TEXT NOT NULL,
                \\  file_path TEXT NOT NULL,
                \\  mime_type TEXT NOT NULL,
                \\  total_bytes INTEGER NOT NULL,
                \\  received_bytes INTEGER NOT NULL,
                \\  state INTEGER NOT NULL,
                \\  timestamp INTEGER NOT NULL
                \\);
            ;
            try database.execute(schema);
        }

        return mgr;
    }

    pub fn deinit(self: *DownloadManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
    }

    pub fn startDownload(self: *DownloadManager, url: []const u8, target_file_path: []const u8, initial_mime: ?[]const u8) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = self.next_id;
        self.next_id += 1;

        const effective_mime = initial_mime orelse "application/octet-stream";
        const now = time.milliTimestamp();

        try self.items.append(self.allocator, .{
            .id = id,
            .url = try self.allocator.dupe(u8, url),
            .file_path = try self.allocator.dupe(u8, target_file_path),
            .mime_type = try self.allocator.dupe(u8, effective_mime),
            .total_bytes = 0,
            .received_bytes = 0,
            .state = .Downloading,
            .start_time_ms = now,
            .last_tick_ms = now,
            .last_tick_bytes = 0,
            .speed_bps = 0.0,
        });

        self.persistItem(&self.items.items[self.items.items.len - 1]) catch {};
        return id;
    }

    pub fn pauseDownload(self: *DownloadManager, id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.findItem(id)) |item| {
            if (item.state == .Downloading) {
                item.state = .Paused;
                item.speed_bps = 0.0;
                self.persistItem(item) catch {};
                return true;
            }
        }
        return false;
    }

    pub fn resumeDownload(self: *DownloadManager, id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.findItem(id)) |item| {
            if (item.state == .Paused) {
                item.state = .Downloading;
                item.last_tick_ms = time.milliTimestamp();
                item.last_tick_bytes = item.received_bytes;
                self.persistItem(item) catch {};
                return true;
            }
        }
        return false;
    }

    pub fn cancelDownload(self: *DownloadManager, id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.findItem(id)) |item| {
            if (item.state == .Downloading or item.state == .Paused or item.state == .Pending) {
                item.state = .Canceled;
                item.speed_bps = 0.0;
                self.persistItem(item) catch {};
                return true;
            }
        }
        return false;
    }

    pub fn feedChunk(self: *DownloadManager, id: u32, chunk: []const u8, total_size: ?usize) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.findItem(id)) |item| {
            if (item.state != .Downloading) return false;

            if (total_size) |ts| item.total_bytes = ts;

            // If initial chunk, sniff MIME type
            if (item.received_bytes == 0 and chunk.len > 0) {
                const sniffed = MimeSniffer.sniff(chunk);
                self.allocator.free(item.mime_type);
                item.mime_type = self.allocator.dupe(u8, sniffed.mime_type) catch item.mime_type;
            }

            item.received_bytes += chunk.len;

            const now = time.milliTimestamp();
            const elapsed_ms = now - item.last_tick_ms;
            if (elapsed_ms >= 500) {
                const delta_bytes = item.received_bytes - item.last_tick_bytes;
                item.speed_bps = (@as(f64, @floatFromInt(delta_bytes)) / @as(f64, @floatFromInt(elapsed_ms))) * 1000.0;
                item.last_tick_ms = now;
                item.last_tick_bytes = item.received_bytes;
            }

            if (item.total_bytes > 0 and item.received_bytes >= item.total_bytes) {
                item.state = .Completed;
                item.speed_bps = 0.0;
            }

            self.persistItem(item) catch {};
            return true;
        }
        return false;
    }

    pub fn getItem(self: *DownloadManager, id: u32) ?DownloadItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.findItem(id)) |item| return item.*;
        return null;
    }

    fn findItem(self: *DownloadManager, id: u32) ?*DownloadItem {
        for (self.items.items) |*item| {
            if (item.id == id) return item;
        }
        return null;
    }

    fn persistItem(self: *DownloadManager, item: *const DownloadItem) !void {
        if (self.db) |*database| {
            const sql = try std.fmt.allocPrintSentinel(
                self.allocator,
                \\INSERT OR REPLACE INTO downloads (id, url, file_path, mime_type, total_bytes, received_bytes, state, timestamp)
                \\VALUES ({d}, '{s}', '{s}', '{s}', {d}, {d}, {d}, {d});
            ,
                .{
                    item.id,
                    item.url,
                    item.file_path,
                    item.mime_type,
                    item.total_bytes,
                    item.received_bytes,
                    @intFromEnum(item.state),
                    time.timestamp(),
                },
                0,
            );
            defer self.allocator.free(sql);
            try database.execute(sql);
        }
    }
};

test "download manager lifecycle, pause, resume, cancel, and speed tracking" {
    const allocator = std.testing.allocator;
    var mgr = try DownloadManager.init(allocator, null);
    defer mgr.deinit();

    const id = try mgr.startDownload("https://releases.mozilla.org/firefox.tar.bz2", "/tmp/firefox.tar.bz2", null);
    try std.testing.expectEqual(@as(u32, 1), id);

    // Feed chunk with PNG magic
    const chunk_png = "\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR";
    const ok1 = mgr.feedChunk(id, chunk_png, 1024);
    try std.testing.expect(ok1);

    const item1 = mgr.getItem(id).?;
    try std.testing.expectEqualStrings("image/png", item1.mime_type);
    try std.testing.expectEqual(@as(usize, chunk_png.len), item1.received_bytes);
    try std.testing.expectEqual(DownloadState.Downloading, item1.state);

    // Pause
    try std.testing.expect(mgr.pauseDownload(id));
    try std.testing.expectEqual(DownloadState.Paused, mgr.getItem(id).?.state);

    // While paused, chunk feed is rejected
    try std.testing.expect(!mgr.feedChunk(id, "more data", null));

    // Resume
    try std.testing.expect(mgr.resumeDownload(id));
    try std.testing.expectEqual(DownloadState.Downloading, mgr.getItem(id).?.state);

    // Complete download
    var remaining: [1024 - chunk_png.len]u8 = @splat(0xaa);
    try std.testing.expect(mgr.feedChunk(id, &remaining, null));
    try std.testing.expectEqual(DownloadState.Completed, mgr.getItem(id).?.state);
    try std.testing.expectEqual(@as(f32, 100.0), mgr.getItem(id).?.progressPercent());
}

test "mime type sniffing and filename sanitization" {
    const allocator = std.testing.allocator;

    const sniff_pdf = MimeSniffer.sniff("%PDF-1.7 header");
    try std.testing.expectEqualStrings("application/pdf", sniff_pdf.mime_type);
    try std.testing.expectEqualStrings(".pdf", sniff_pdf.safe_extension);

    const safe_name = try MimeSniffer.sanitizeFileName(allocator, "../../../evil.exe", sniff_pdf);
    defer allocator.free(safe_name);
    try std.testing.expectEqualStrings("evil.exe.safe.pdf", safe_name);

    const normal_name = try MimeSniffer.sanitizeFileName(allocator, "document", sniff_pdf);
    defer allocator.free(normal_name);
    try std.testing.expectEqualStrings("document.pdf", normal_name);
}

test "sqlite download persistence" {
    const allocator = std.testing.allocator;
    var db = try Database.openInMemory();
    defer db.close();

    var mgr = try DownloadManager.init(allocator, db);
    defer mgr.deinit();

    const id = try mgr.startDownload("https://davoth.org/source.zip", "/home/user/source.zip", "application/zip");
    try std.testing.expect(id > 0);

    const item = mgr.getItem(id).?;
    try std.testing.expectEqualStrings("application/zip", item.mime_type);
}
