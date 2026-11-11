//! Bitwarden Vault data model, credential lookup, and secure memory sanitization.
const std = @import("std");
const crypto = @import("crypto.zig");

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
        crypto.secureZero(@constCast(self.password));
        if (self.totp) |t| crypto.secureZero(@constCast(t));
        allocator.free(self.uri);
        allocator.free(self.username);
        allocator.free(self.password);
        if (self.totp) |t| allocator.free(t);
    }
};

pub const CardData = struct {
    cardholder_name: []const u8,
    brand: []const u8,
    number: []const u8,
    exp_month: []const u8,
    exp_year: []const u8,
    code: []const u8,

    pub fn deinit(self: *CardData, allocator: std.mem.Allocator) void {
        crypto.secureZero(@constCast(self.number));
        crypto.secureZero(@constCast(self.code));
        allocator.free(self.cardholder_name);
        allocator.free(self.brand);
        allocator.free(self.number);
        allocator.free(self.exp_month);
        allocator.free(self.exp_year);
        allocator.free(self.code);
    }
};

pub const IdentityData = struct {
    title: []const u8,
    first_name: []const u8,
    last_name: []const u8,
    address1: []const u8,
    city: []const u8,
    state: []const u8,
    postal_code: []const u8,
    country: []const u8,
    email: []const u8,
    phone: []const u8,
    ssn: ?[]const u8 = null,

    pub fn deinit(self: *IdentityData, allocator: std.mem.Allocator) void {
        if (self.ssn) |s| crypto.secureZero(@constCast(s));
        allocator.free(self.title);
        allocator.free(self.first_name);
        allocator.free(self.last_name);
        allocator.free(self.address1);
        allocator.free(self.city);
        allocator.free(self.state);
        allocator.free(self.postal_code);
        allocator.free(self.country);
        allocator.free(self.email);
        allocator.free(self.phone);
        if (self.ssn) |s| allocator.free(s);
    }
};

pub const Cipher = struct {
    id: []const u8,
    cipher_type: CipherType,
    name: []const u8,
    notes: ?[]const u8 = null,
    login: ?LoginData = null,
    card: ?CardData = null,
    identity: ?IdentityData = null,
    favorite: bool = false,

    pub fn deinit(self: *Cipher, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        if (self.notes) |n| {
            crypto.secureZero(@constCast(n));
            allocator.free(n);
        }
        if (self.login) |*l| l.deinit(allocator);
        if (self.card) |*c| c.deinit(allocator);
        if (self.identity) |*i| i.deinit(allocator);
    }
};

pub const Vault = struct {
    allocator: std.mem.Allocator,
    ciphers: std.ArrayList(Cipher),
    is_unlocked: bool = false,
    session_keys: ?crypto.DerivedKeys = null,

    pub fn init(allocator: std.mem.Allocator) Vault {
        return .{
            .allocator = allocator,
            .ciphers = .empty,
            .is_unlocked = false,
            .session_keys = null,
        };
    }

    pub fn deinit(self: *Vault) void {
        self.lock();
        self.ciphers.deinit(self.allocator);
    }

    /// Locks the vault and securely wipes all credentials and keys from memory
    pub fn lock(self: *Vault) void {
        for (self.ciphers.items) |*c| {
            c.deinit(self.allocator);
        }
        self.ciphers.clearRetainingCapacity();
        if (self.session_keys) |*k| {
            k.wipe();
            self.session_keys = null;
        }
        self.is_unlocked = false;
    }

    pub fn unlock(self: *Vault, keys: crypto.DerivedKeys) void {
        self.session_keys = keys;
        self.is_unlocked = true;
    }

    pub fn addCipher(self: *Vault, cipher: Cipher) !void {
        try self.ciphers.append(self.allocator, cipher);
    }

    pub fn findLoginsForHost(self: *const Vault, allocator: std.mem.Allocator, host: []const u8) !std.ArrayList(*const Cipher) {
        var results: std.ArrayList(*const Cipher) = .empty;
        errdefer results.deinit(allocator);

        if (!self.is_unlocked) return results;

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

test "vault add, lock and find logins" {
    const allocator = std.testing.allocator;
    var vault = Vault.init(allocator);
    defer vault.deinit();

    const keys = crypto.deriveEncryptionKeys(@splat(1));
    vault.unlock(keys);

    try vault.addCipher(.{
        .id = try allocator.dupe(u8, "cipher-1"),
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

    // Test lock clears and wipes entries
    vault.lock();
    try std.testing.expect(!vault.is_unlocked);
    try std.testing.expectEqual(@as(usize, 0), vault.ciphers.items.len);
}
