//! Bitwarden native browser interface dialogs and popups.
const std = @import("std");
const Vault = @import("vault.zig").Vault;
const generatePassword = @import("crypto.zig").generatePassword;

pub const BitwardenUI = struct {
    vault: *Vault,
    is_popup_open: bool = false,

    pub fn init(vault: *Vault) BitwardenUI {
        return .{
            .vault = vault,
            .is_popup_open = false,
        };
    }

    pub fn generateNewPassword(self: *BitwardenUI, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return generatePassword(allocator, 16, true, true, true, true);
    }
};
