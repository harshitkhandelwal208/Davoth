//! Linux AT-SPI DBus bridge for screen readers (Orca).
const std = @import("std");

pub const AtspiBridge = struct {
    is_active: bool = false,

    pub fn init() AtspiBridge {
        return .{ .is_active = true };
    }

    pub fn notifyFocusGained(_: *AtspiBridge, _: []const u8) void {}
};
