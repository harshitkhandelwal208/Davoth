//! Picture-in-Picture floating video playback window.
const std = @import("std");

pub const PipWindow = struct {
    is_active: bool = false,
    video_source_url: []const u8 = "",

    pub fn open(self: *PipWindow, url: []const u8) void {
        self.video_source_url = url;
        self.is_active = true;
    }

    pub fn close(self: *PipWindow) void {
        self.is_active = false;
    }
};
