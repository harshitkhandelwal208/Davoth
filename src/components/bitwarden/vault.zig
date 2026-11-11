//! Bitwarden Vault data model and credential lookup.
const std = @import("std");

pub const CipherType = enum(u8) {
    Login = 1,
    SecureNote = 2,
    Card = 3,
    Identity = 4,
};

pub const LoginData = struct {
    uri: []const u8,
    username: []const u8,
    password: []const u8,
    totp: ?[]const u8 = null,

    pub fn deinit(self: *LoginData, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        allocator.free(self.username);
        allocator.free(self.password);
        if (self.totp) |t| allocator.free(t);
    }
};

pub const Cipher = struct {
    id: []const u8,
    cipher_type: CipherType,
    name: []const u8,
    notes: ?[]const u8 = null,
    login: ?LoginData = null,
    favorite: bool = false,

    pub fn deinit(self: *Cipher, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        if (self.notes) |n| allocator.free(n);
        if (self.login) |*l| l.deinit(allocator);
    }
};

pub const Vault = struct {
    allocator: std.mem.Allocator,
    ciphers: std.ArrayList(Cipher),
    is_unlocked: bool = false,

    pub fn init(allocator: std.mem.Allocator) Vault {
        return .{
            .allocator = allocator,
            .ciphers = .empty,
            .is_unlocked = false,
        };
    }

    pub fn deinit(self: *Vault) void {
        for (self.ciphers.items) |*c| {
            c.deinit(self.allocator);
        }
        self.ciphers.deinit(self.allocator);
    }

    pub fn addCipher(self: *Vault, cipher: Cipher) !void {
        try self.ciphers.append(self.allocator, cipher);
    }

    pub fn findLoginsForHost(self: *const Vault, allocator: std.mem.Allocator, host: []const u8) !std.ArrayList(*const Cipher) {
        var results: std.ArrayList(*const Cipher) = .empty;
        errdefer results.deinit(allocator);

        for (self.ciphers.items) |*c| {
            if (c.cipher_type == .Login and c.login != null) {
                if (std.mem.indexOf(u8, c.login.?.uri, host) != null) {
                    try results.append(allocator, c);
                }
            }
        }

        return results;
    }
};

test "vault add and find logins" {
    const allocator = std.testing.allocator;
    var vault = Vault.init(allocator);
    defer vault.deinit();

    try vault.addCipher(.{
        .id = try allocator.dupe(u8, "1"),
        .cipher_type = .Login,
        .name = try allocator.dupe(u8, "Davoth Account"),
        .login = .{
            .uri = try allocator.dupe(u8, "https://davoth.org"),
            .username = try allocator.dupe(u8, "user@davoth.org"),
            .password = try allocator.dupe(u8, "P@ssw0rd123"),
        },
    });

    var results = try vault.findLoginsForHost(allocator, "davoth.org");
    defer results.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqualStrings("user@davoth.org", results.items[0].login.?.username);
}
