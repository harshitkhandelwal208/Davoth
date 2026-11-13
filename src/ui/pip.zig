//! Picture-in-Picture (PiP) video playback window subsystem.
//! Firefox parity: floating video overlay with transport controls, seek, volume,
//! multi-window support, corner snapping, subtitles, and return-to-tab restoration.

const std = @import("std");

pub const PipState = enum {
    Closed,
    Playing,
    Paused,
    Buffering,
    Ended,
};

pub const PipCorner = enum {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
    Custom,
};

pub const PipDisplayItemType = enum {
    Background,
    VideoFrame,
    ControlOverlay,
    PlayPauseButton,
    ProgressBar,
    VolumeSlider,
    TimeLabel,
    SubtitleText,
    CloseButton,
    ReturnToTabButton,
};

pub const PipDisplayItem = struct {
    item_type: PipDisplayItemType,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: u32,
    text: ?[]const u8 = null,
};

pub const PipWindow = struct {
    allocator: std.mem.Allocator,
    id: u32,
    tab_id: u32,
    title: []const u8,
    video_source_url: []const u8,
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 420.0,
    height: f32 = 236.25, // 16:9 aspect ratio
    current_time: f64 = 0.0,
    duration: f64 = 0.0,
    volume: f32 = 1.0,
    is_muted: bool = false,
    playback_rate: f32 = 1.0,
    state: PipState = .Closed,
    corner: PipCorner = .BottomRight,
    subtitles_enabled: bool = false,
    current_subtitle: ?[]const u8 = null,
    controls_visible: bool = true,
    is_fullscreen: bool = false,
    is_pinned_on_top: bool = true,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u32,
        tab_id: u32,
        title: []const u8,
        url: []const u8,
        duration: f64,
    ) !*PipWindow {
        const win = try allocator.create(PipWindow);
        win.* = .{
            .allocator = allocator,
            .id = id,
            .tab_id = tab_id,
            .title = try allocator.dupe(u8, title),
            .video_source_url = try allocator.dupe(u8, url),
            .duration = if (duration >= 0.0) duration else 0.0,
            .state = .Playing,
        };
        win.snapToCorner(.BottomRight, 1920.0, 1080.0);
        return win;
    }

    pub fn deinit(self: *PipWindow) void {
        self.allocator.free(self.title);
        self.allocator.free(self.video_source_url);
        if (self.current_subtitle) |s| self.allocator.free(s);
        self.allocator.destroy(self);
    }

    pub fn play(self: *PipWindow) void {
        if (self.state != .Closed) {
            self.state = .Playing;
        }
    }

    pub fn pause(self: *PipWindow) void {
        if (self.state != .Closed) {
            self.state = .Paused;
        }
    }

    pub fn togglePlay(self: *PipWindow) void {
        if (self.state == .Playing) {
            self.pause();
        } else if (self.state == .Paused or self.state == .Ended) {
            self.play();
        }
    }

    pub fn seek(self: *PipWindow, target_seconds: f64) void {
        const clamped = std.math.clamp(target_seconds, 0.0, self.duration);
        self.current_time = clamped;
        if (self.current_time >= self.duration and self.duration > 0.0) {
            self.state = .Ended;
        }
    }

    pub fn seekRelative(self: *PipWindow, delta_seconds: f64) void {
        self.seek(self.current_time + delta_seconds);
    }

    pub fn setVolume(self: *PipWindow, vol: f32) void {
        self.volume = std.math.clamp(vol, 0.0, 1.0);
        if (self.volume > 0.0) {
            self.is_muted = false;
        }
    }

    pub fn toggleMute(self: *PipWindow) void {
        self.is_muted = !self.is_muted;
    }

    pub fn getEffectiveVolume(self: *const PipWindow) f32 {
        if (self.is_muted) return 0.0;
        return self.volume;
    }

    pub fn setPlaybackRate(self: *PipWindow, rate: f32) void {
        if (rate > 0.0 and rate <= 16.0) {
            self.playback_rate = rate;
        }
    }

    pub fn setSubtitle(self: *PipWindow, text: ?[]const u8) !void {
        if (self.current_subtitle) |s| {
            self.allocator.free(s);
            self.current_subtitle = null;
        }
        if (text) |t| {
            self.current_subtitle = try self.allocator.dupe(u8, t);
            self.subtitles_enabled = true;
        } else {
            self.subtitles_enabled = false;
        }
    }

    pub fn toggleSubtitles(self: *PipWindow) void {
        self.subtitles_enabled = !self.subtitles_enabled;
    }

    pub fn snapToCorner(self: *PipWindow, corner: PipCorner, screen_w: f32, screen_h: f32) void {
        const margin: f32 = 24.0;
        self.corner = corner;
        switch (corner) {
            .TopLeft => {
                self.x = margin;
                self.y = margin;
            },
            .TopRight => {
                self.x = @max(0.0, screen_w - self.width - margin);
                self.y = margin;
            },
            .BottomLeft => {
                self.x = margin;
                self.y = @max(0.0, screen_h - self.height - margin);
            },
            .BottomRight => {
                self.x = @max(0.0, screen_w - self.width - margin);
                self.y = @max(0.0, screen_h - self.height - margin);
            },
            .Custom => {},
        }
    }

    pub fn resize(self: *PipWindow, new_w: f32, new_h: f32) void {
        self.width = @max(160.0, new_w);
        self.height = @max(90.0, new_h);
    }

    pub fn returnToTab(self: *PipWindow) u32 {
        self.state = .Closed;
        return self.tab_id;
    }

    pub fn close(self: *PipWindow) void {
        self.state = .Closed;
    }

    pub fn renderHtml(self: *const PipWindow, allocator: std.mem.Allocator) ![]u8 {
        const play_icon = if (self.state == .Playing) "⏸" else "▶";
        const mute_icon = if (self.is_muted or self.volume == 0.0) "🔇" else "🔊";
        const sub_icon = if (self.subtitles_enabled) "🗩 On" else "🗩 Off";
        const progress_pct: f32 = if (self.duration > 0.0)
            @floatCast((self.current_time / self.duration) * 100.0)
        else
            0.0;

        return try std.fmt.allocPrint(
            allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <meta charset="utf-8">
            \\  <title>{s} - Picture-in-Picture</title>
            \\  <style>
            \\    body {{ margin: 0; padding: 0; background: #000000; color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; overflow: hidden; user-select: none; }}
            \\    .pip-container {{ position: relative; width: 100vw; height: 100vh; display: flex; flex-direction: column; justify-content: space-between; }}
            \\    .video-surface {{ position: absolute; inset: 0; background: #121216; display: flex; align-items: center; justify-content: center; }}
            \\    .subtitle {{ position: absolute; bottom: 50px; width: 100%; text-align: center; color: #ffeb3b; font-size: 16px; font-weight: bold; text-shadow: 0 2px 4px rgba(0,0,0,0.8); }}
            \\    .controls {{ position: relative; z-index: 10; background: linear-gradient(transparent, rgba(0,0,0,0.85)); padding: 8px 12px; display: flex; align-items: center; gap: 8px; }}
            \\    .btn {{ background: rgba(255,255,255,0.15); border: none; color: white; border-radius: 4px; padding: 6px 10px; cursor: pointer; font-size: 14px; transition: background 0.15s; }}
            \\    .btn:hover {{ background: rgba(255,255,255,0.3); }}
            \\    .progress-bar {{ flex: 1; height: 5px; background: rgba(255,255,255,0.3); border-radius: 3px; position: relative; cursor: pointer; }}
            \\    .progress-fill {{ width: {d:.1}%; height: 100%; background: #388bfd; border-radius: 3px; }}
            \\    .time-badge {{ font-size: 12px; color: #cccccc; }}
            \\    .top-bar {{ position: absolute; top: 0; left: 0; right: 0; padding: 6px 10px; display: flex; justify-content: space-between; align-items: center; background: linear-gradient(rgba(0,0,0,0.7), transparent); z-index: 10; }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="pip-container">
            \\    <div class="top-bar">
            \\      <span style="font-size: 13px; font-weight: 500; text-overflow: ellipsis; overflow: hidden; white-space: nowrap;">{s}</span>
            \\      <div>
            \\        <button class="btn" title="Back to tab">↖ Tab</button>
            \\        <button class="btn" title="Close">✕</button>
            \\      </div>
            \\    </div>
            \\    <div class="video-surface">
            \\      <span style="color: #666;">[PiP Stream: {s}]</span>
            \\    </div>
            \\    {s}
            \\    <div class="controls">
            \\      <button class="btn">{s}</button>
            \\      <button class="btn">-10s</button>
            \\      <button class="btn">+10s</button>
            \\      <div class="progress-bar"><div class="progress-fill"></div></div>
            \\      <span class="time-badge">{d:.0}s / {d:.0}s</span>
            \\      <button class="btn">{s}</button>
            \\      <button class="btn">{s}</button>
            \\    </div>
            \\  </div>
            \\</body>
            \\</html>
        ,
            .{
                self.title,
                progress_pct,
                self.title,
                self.video_source_url,
                if (self.subtitles_enabled and self.current_subtitle != null)
                    "<div class=\"subtitle\">Active Subtitle</div>"
                else
                    "",
                play_icon,
                self.current_time,
                self.duration,
                mute_icon,
                sub_icon,
            },
        );
    }
};

pub const PipManager = struct {
    allocator: std.mem.Allocator,
    windows: std.ArrayList(*PipWindow),
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) PipManager {
        return .{
            .allocator = allocator,
            .windows = .empty,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *PipManager) void {
        for (self.windows.items) |win| {
            win.deinit();
        }
        self.windows.deinit(self.allocator);
    }

    pub fn openPip(
        self: *PipManager,
        tab_id: u32,
        title: []const u8,
        url: []const u8,
        duration: f64,
    ) !*PipWindow {
        // If this tab already has a PiP window, return it
        if (self.findPipByTab(tab_id)) |existing| {
            existing.state = .Playing;
            return existing;
        }

        const id = self.next_id;
        self.next_id += 1;

        const win = try PipWindow.init(self.allocator, id, tab_id, title, url, duration);
        try self.windows.append(self.allocator, win);
        return win;
    }

    pub fn closePip(self: *PipManager, id: u32) bool {
        var i: usize = 0;
        while (i < self.windows.items.len) : (i += 1) {
            if (self.windows.items[i].id == id) {
                const win = self.windows.orderedRemove(i);
                win.deinit();
                return true;
            }
        }
        return false;
    }

    pub fn findPipByTab(self: *PipManager, tab_id: u32) ?*PipWindow {
        for (self.windows.items) |win| {
            if (win.tab_id == tab_id) {
                return win;
            }
        }
        return null;
    }

    pub fn findPipById(self: *PipManager, id: u32) ?*PipWindow {
        for (self.windows.items) |win| {
            if (win.id == id) {
                return win;
            }
        }
        return null;
    }

    pub fn activePipCount(self: *const PipManager) usize {
        var count: usize = 0;
        for (self.windows.items) |win| {
            if (win.state != .Closed) count += 1;
        }
        return count;
    }

    pub fn closeAll(self: *PipManager) void {
        for (self.windows.items) |win| {
            win.deinit();
        }
        self.windows.clearRetainingCapacity();
    }
};

test "pip window lifecycle and transport controls" {
    const allocator = std.testing.allocator;
    var pip = try PipWindow.init(allocator, 1, 10, "Firefox PiP Video", "https://video.example.com/stream.mp4", 120.0);
    defer pip.deinit();

    try std.testing.expectEqual(PipState.Playing, pip.state);
    try std.testing.expectEqual(@as(f64, 120.0), pip.duration);
    try std.testing.expectEqual(@as(f64, 0.0), pip.current_time);

    // Pause and Play toggle
    pip.togglePlay();
    try std.testing.expectEqual(PipState.Paused, pip.state);
    pip.togglePlay();
    try std.testing.expectEqual(PipState.Playing, pip.state);

    // Seek forward and back
    pip.seekRelative(45.0);
    try std.testing.expectEqual(@as(f64, 45.0), pip.current_time);
    pip.seekRelative(-10.0);
    try std.testing.expectEqual(@as(f64, 35.0), pip.current_time);
    pip.seek(130.0); // clamped to duration
    try std.testing.expectEqual(@as(f64, 120.0), pip.current_time);
    try std.testing.expectEqual(PipState.Ended, pip.state);

    // Volume and Muting
    pip.setVolume(0.75);
    try std.testing.expectEqual(@as(f32, 0.75), pip.volume);
    try std.testing.expectEqual(@as(f32, 0.75), pip.getEffectiveVolume());
    pip.toggleMute();
    try std.testing.expectEqual(@as(f32, 0.0), pip.getEffectiveVolume());
    pip.toggleMute();
    try std.testing.expectEqual(@as(f32, 0.75), pip.getEffectiveVolume());

    // Corner snapping
    pip.snapToCorner(.TopLeft, 1920.0, 1080.0);
    try std.testing.expectEqual(@as(f32, 24.0), pip.x);
    try std.testing.expectEqual(@as(f32, 24.0), pip.y);

    pip.snapToCorner(.BottomRight, 1920.0, 1080.0);
    try std.testing.expect(pip.x > 1000.0);
    try std.testing.expect(pip.y > 800.0);

    // Subtitles
    try pip.setSubtitle("Hello world from Davoth PiP!");
    try std.testing.expect(pip.subtitles_enabled);
    try std.testing.expect(pip.current_subtitle != null);

    // Render HTML
    const html = try pip.renderHtml(allocator);
    defer allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "Picture-in-Picture") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Firefox PiP Video") != null);

    // Return to tab
    const tab = pip.returnToTab();
    try std.testing.expectEqual(@as(u32, 10), tab);
    try std.testing.expectEqual(PipState.Closed, pip.state);
}

test "pip manager multi-window handling" {
    const allocator = std.testing.allocator;
    var mgr = PipManager.init(allocator);
    defer mgr.deinit();

    const w1 = try mgr.openPip(1, "Video 1", "https://site.com/1.mp4", 60.0);
    const w2 = try mgr.openPip(2, "Video 2", "https://site.com/2.mp4", 90.0);

    try std.testing.expectEqual(@as(usize, 2), mgr.activePipCount());
    try std.testing.expectEqual(w1, mgr.findPipByTab(1).?);
    try std.testing.expectEqual(w2, mgr.findPipByTab(2).?);

    // Opening same tab returns existing
    const w1_dup = try mgr.openPip(1, "Ignored", "Ignored", 10.0);
    try std.testing.expectEqual(w1, w1_dup);
    try std.testing.expectEqual(@as(usize, 2), mgr.activePipCount());

    // Close window 1
    try std.testing.expect(mgr.closePip(w1.id));
    try std.testing.expectEqual(@as(usize, 1), mgr.activePipCount());
    try std.testing.expect(mgr.findPipByTab(1) == null);
}
