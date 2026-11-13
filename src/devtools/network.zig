//! Network traffic inspector and waterfall timeline analyzer.
//! Provides Firefox-parity network timing phases (DNS, TCP, TLS, TTFB, Download),
//! request status tracking, and HTML/CSS waterfall visualization.

const std = @import("std");

pub const NetworkPhase = enum {
    DNS,
    TCP,
    TLS,
    TTFB,
    Download,
};

pub const WaterfallTiming = struct {
    start_offset_ms: u64 = 0,
    dns_ms: u32 = 0,
    tcp_ms: u32 = 0,
    tls_ms: u32 = 0,
    ttfb_ms: u32 = 0,
    download_ms: u32 = 0,
    total_ms: u64 = 0,

    pub fn computeTotal(self: *WaterfallTiming) void {
        self.total_ms = @as(u64, self.dns_ms) +
            @as(u64, self.tcp_ms) +
            @as(u64, self.tls_ms) +
            @as(u64, self.ttfb_ms) +
            @as(u64, self.download_ms);
    }
};

pub const NetworkRequestEntry = struct {
    url: []const u8,
    method: []const u8,
    status: u16,
    mime_type: []const u8,
    size_bytes: usize,
    timing: WaterfallTiming,
    initiator: []const u8 = "parser",

    pub fn deinit(self: *NetworkRequestEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.method);
        allocator.free(self.mime_type);
        allocator.free(self.initiator);
    }
};

// Backwards-compatible struct
pub const NetworkLogEntry = struct {
    url: []const u8,
    method: []const u8,
    status: u16,
    size_bytes: usize,
    duration_ms: u64,
};

pub const NetworkSummary = struct {
    total_requests: usize,
    total_bytes: usize,
    total_duration_ms: u64,
};

pub const NetworkInspector = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayList(NetworkRequestEntry),
    // Backwards-compatible entries array
    entries: std.ArrayList(NetworkLogEntry),

    pub fn init(allocator: std.mem.Allocator) NetworkInspector {
        return .{
            .allocator = allocator,
            .requests = .empty,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *NetworkInspector) void {
        for (self.requests.items) |*r| {
            r.deinit(self.allocator);
        }
        self.requests.deinit(self.allocator);

        for (self.entries.items) |e| {
            self.allocator.free(e.url);
            self.allocator.free(e.method);
        }
        self.entries.deinit(self.allocator);
    }

    /// Records a detailed network request with waterfall timing phases
    pub fn recordRequest(
        self: *NetworkInspector,
        url: []const u8,
        method: []const u8,
        status: u16,
        mime_type: []const u8,
        size_bytes: usize,
        timing: WaterfallTiming,
        initiator: []const u8,
    ) !void {
        var t = timing;
        if (t.total_ms == 0) t.computeTotal();

        try self.requests.append(self.allocator, .{
            .url = try self.allocator.dupe(u8, url),
            .method = try self.allocator.dupe(u8, method),
            .status = status,
            .mime_type = try self.allocator.dupe(u8, mime_type),
            .size_bytes = size_bytes,
            .timing = t,
            .initiator = try self.allocator.dupe(u8, initiator),
        });

        // Also append to backwards-compatible entries list
        try self.entries.append(self.allocator, .{
            .url = try self.allocator.dupe(u8, url),
            .method = try self.allocator.dupe(u8, method),
            .status = status,
            .size_bytes = size_bytes,
            .duration_ms = t.total_ms,
        });
    }

    /// Backwards compatibility method
    pub fn logRequest(self: *NetworkInspector, url: []const u8, method: []const u8, status: u16, size: usize, duration: u64) !void {
        var timing = WaterfallTiming{
            .start_offset_ms = 0,
            .dns_ms = 5,
            .tcp_ms = 10,
            .tls_ms = 15,
            .ttfb_ms = @as(u32, @truncate(@min(duration, 30))),
            .download_ms = @as(u32, @truncate(if (duration > 60) duration - 60 else 10)),
        };
        timing.computeTotal();

        try self.recordRequest(url, method, status, "text/html", size, timing, "navigation");
    }

    /// Computes aggregate statistics across all logged requests
    pub fn getSummary(self: *const NetworkInspector) NetworkSummary {
        var total_bytes: usize = 0;
        var max_end: u64 = 0;

        for (self.requests.items) |r| {
            total_bytes += r.size_bytes;
            const req_end = r.timing.start_offset_ms + r.timing.total_ms;
            if (req_end > max_end) max_end = req_end;
        }

        return .{
            .total_requests = self.requests.items.len,
            .total_bytes = total_bytes,
            .total_duration_ms = max_end,
        };
    }

    /// Renders an interactive HTML waterfall timeline representation
    pub fn renderWaterfallTimelineHtml(self: *const NetworkInspector) ![]u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(self.allocator);

        const summary = self.getSummary();
        const max_time = @max(summary.total_duration_ms, 1);

        const header_str = try std.fmt.allocPrint(self.allocator,
            \\<div class="network-waterfall" style="font-family: monospace; background: #1e1e2e; color: #cdd6f4; padding: 12px; border-radius: 6px;">
            \\  <div class="waterfall-header" style="display: flex; justify-content: space-between; border-bottom: 1px solid #45475a; padding-bottom: 8px; margin-bottom: 8px;">
            \\    <span>Requests: <strong>{d}</strong></span>
            \\    <span>Transferred: <strong>{d} B</strong></span>
            \\    <span>Finish: <strong>{d} ms</strong></span>
            \\  </div>
            \\
        , .{ summary.total_requests, summary.total_bytes, summary.total_duration_ms });
        defer self.allocator.free(header_str);
        try buf.appendSlice(self.allocator, header_str);

        for (self.requests.items) |req| {
            const status_color = if (req.status < 300) "#a6e3a1" else if (req.status < 400) "#f9e2af" else "#f38ba8";
            const left_pct = (@as(f64, @floatFromInt(req.timing.start_offset_ms)) / @as(f64, @floatFromInt(max_time))) * 100.0;
            const width_pct = @max((@as(f64, @floatFromInt(req.timing.total_ms)) / @as(f64, @floatFromInt(max_time))) * 100.0, 1.0);

            const row_str = try std.fmt.allocPrint(self.allocator,
                \\  <div class="waterfall-row" style="display: grid; grid-template-columns: 80px 60px 1fr 200px; gap: 8px; align-items: center; padding: 4px 0; border-bottom: 1px solid #313244;">
                \\    <span style="color: {s};">{d}</span>
                \\    <span>{s}</span>
                \\    <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{s}</span>
                \\    <div style="position: relative; width: 100%; height: 14px; background: #313244; border-radius: 2px;">
                \\      <div style="position: absolute; left: {d:.1}%; width: {d:.1}%; height: 100%; background: #89b4fa; border-radius: 2px;" title="{d} ms"></div>
                \\    </div>
                \\  </div>
                \\
            , .{
                status_color,
                req.status,
                req.method,
                req.url,
                left_pct,
                width_pct,
                req.timing.total_ms,
            });
            defer self.allocator.free(row_str);
            try buf.appendSlice(self.allocator, row_str);
        }

        try buf.appendSlice(self.allocator, "</div>");
        return try buf.toOwnedSlice(self.allocator);
    }
};

test "network inspector waterfall request recording and summary metrics" {
    const allocator = std.testing.allocator;
    var inspector = NetworkInspector.init(allocator);
    defer inspector.deinit();

    try inspector.recordRequest(
        "https://davoth.org/index.html",
        "GET",
        200,
        "text/html",
        15400,
        .{
            .start_offset_ms = 0,
            .dns_ms = 12,
            .tcp_ms = 18,
            .tls_ms = 24,
            .ttfb_ms = 35,
            .download_ms = 20,
        },
        "navigation",
    );

    try inspector.recordRequest(
        "https://davoth.org/bundle.js",
        "GET",
        200,
        "application/javascript",
        48200,
        .{
            .start_offset_ms = 40,
            .dns_ms = 0,
            .tcp_ms = 0,
            .tls_ms = 0,
            .ttfb_ms = 15,
            .download_ms = 45,
        },
        "script",
    );

    try std.testing.expectEqual(@as(usize, 2), inspector.requests.items.len);
    try std.testing.expectEqual(@as(usize, 2), inspector.entries.items.len);

    const summary = inspector.getSummary();
    try std.testing.expectEqual(@as(usize, 2), summary.total_requests);
    try std.testing.expectEqual(@as(usize, 63600), summary.total_bytes);
    try std.testing.expect(summary.total_duration_ms >= 100);

    // Verify HTML waterfall generation
    const html = try inspector.renderWaterfallTimelineHtml();
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "network-waterfall") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "davoth.org/index.html") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "davoth.org/bundle.js") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "200") != null);
}
