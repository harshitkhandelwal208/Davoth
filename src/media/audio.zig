//! Audio output stream abstraction.
const std = @import("std");

pub const AudioFormat = struct {
    sample_rate: u32 = 44100,
    channels: u16 = 2,
    bits_per_sample: u16 = 16,
};

pub const AudioStream = struct {
    format: AudioFormat,
    is_playing: bool = false,

    pub fn init(format: AudioFormat) AudioStream {
        return .{
            .format = format,
            .is_playing = false,
        };
    }

    pub fn start(self: *AudioStream) void {
        self.is_playing = true;
    }

    pub fn stop(self: *AudioStream) void {
        self.is_playing = false;
    }
};
