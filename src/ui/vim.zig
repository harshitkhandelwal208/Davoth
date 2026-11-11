//! Configurable Vim-style keyboard navigation mode and link hint markers.
const std = @import("std");

pub const VimMode = enum {
    Normal,
    Insert,
    Hint,
};

pub const VimNavigator = struct {
    mode: VimMode = .Normal,
    scroll_offset: f32 = 0.0,
    hint_buffer: [4]u8 = undefined,
    hint_len: usize = 0,

    pub fn handleKey(self: *VimNavigator, key: u8) ?enum { ScrollDown, ScrollUp, ScrollTop, ScrollBottom, CloseTab, NewTab, EnterHintMode } {
        if (self.mode == .Normal) {
            switch (key) {
                'j' => {
                    self.scroll_offset += 50.0;
                    return .ScrollDown;
                },
                'k' => {
                    self.scroll_offset = @max(0.0, self.scroll_offset - 50.0);
                    return .ScrollUp;
                },
                'd' => return .CloseTab,
                't' => return .NewTab,
                'f' => {
                    self.mode = .Hint;
                    self.hint_len = 0;
                    return .EnterHintMode;
                },
                'i' => {
                    self.mode = .Insert;
                    return null;
                },
                else => return null,
            }
        } else if (self.mode == .Hint) {
            if (key == 27) { // Escape
                self.mode = .Normal;
            }
        }
        return null;
    }
};

test "vim navigator key handling" {
    var vim = VimNavigator{};
    try std.testing.expectEqual(VimMode.Normal, vim.mode);

    const act = vim.handleKey('j');
    try std.testing.expect(act != null);
    try std.testing.expectEqual(@as(f32, 50.0), vim.scroll_offset);
}
