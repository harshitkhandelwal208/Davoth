//! HTMLMediaElement (Audio/Video) state machine and playback interface.
const std = @import("std");

pub const MediaReadyState = enum(u8) {
    HaveNothing = 0,
    HaveMetadata = 1,
    HaveCurrentData = 2,
    HaveFutureData = 3,
    HaveEnoughData = 4,
};

pub const HTMLMediaElement = struct {
    src: []const u8 = "",
    current_time: f64 = 0.0,
    duration: f64 = 0.0,
    paused: bool = true,
    ended: bool = false,
    volume: f32 = 1.0,
    muted: bool = false,
    playback_rate: f32 = 1.0,
    ready_state: MediaReadyState = .HaveNothing,

    pub fn play(self: *HTMLMediaElement) void {
        self.paused = false;
        self.ended = false;
    }

    pub fn pause(self: *HTMLMediaElement) void {
        self.paused = true;
    }

    pub fn seek(self: *HTMLMediaElement, time: f64) void {
        self.current_time = @max(0.0, @min(self.duration, time));
    }
};

test "media element play and seek" {
    var media = HTMLMediaElement{ .duration = 120.0 };
    try std.testing.expect(media.paused);

    media.play();
    try std.testing.expect(!media.paused);

    media.seek(45.0);
    try std.testing.expectEqual(@as(f64, 45.0), media.current_time);
}
