//! Bitwarden server API synchronization protocol and vault deserialization.
const std = @import("std");
const HttpClient = @import("../../net/http1.zig").HttpClient;
const Vault = @import("vault.zig").Vault;
const Cipher = @import("vault.zig").Cipher;
const CipherType = @import("vault.zig").CipherType;
const LoginData = @import("vault.zig").LoginData;
const crypto = @import("crypto.zig");
const DerivedKeys = crypto.DerivedKeys;

pub const BitwardenSyncClient = struct {
    allocator: std.mem.Allocator,
    server_url: []const u8 = "https://vault.bitwarden.com",
    access_token: ?[]const u8 = null,
    refresh_token: ?[]const u8 = null,
    kdf_iterations: u32 = 600000,

    pub fn init(allocator: std.mem.Allocator, server_url: []const u8) BitwardenSyncClient {
        return .{
            .allocator = allocator,
            .server_url = server_url,
            .access_token = null,
            .refresh_token = null,
            .kdf_iterations = 600000,
        };
    }

    pub fn deinit(self: *BitwardenSyncClient) void {
        if (self.access_token) |t| self.allocator.free(t);
        if (self.refresh_token) |r| self.allocator.free(r);
    }

    pub fn setAccessToken(self: *BitwardenSyncClient, token: []const u8) !void {
        if (self.access_token) |t| self.allocator.free(t);
        self.access_token = try self.allocator.dupe(u8, token);
    }

    pub fn setRefreshToken(self: *BitwardenSyncClient, token: []const u8) !void {
        if (self.refresh_token) |r| self.allocator.free(r);
        self.refresh_token = try self.allocator.dupe(u8, token);
    }

    /// Formats the OAuth2 form-urlencoded token request body
    pub fn buildLoginRequestBody(self: *BitwardenSyncClient, email: []const u8, password_hash: []const u8) ![]u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "grant_type=password&username={s}&password={s}&scope=api%20offline_access&client_id=web",
            .{ email, password_hash },
        );
    }

    /// Parses the server's sync payload (JSON) and decrypts all ciphers into the vault
    pub fn parseAndPopulateVault(self: *BitwardenSyncClient, json_bytes: []const u8, keys: *const DerivedKeys, vault: *Vault) !usize {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_bytes, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidSyncPayload;

        const ciphers_val = root.object.get("ciphers") orelse root.object.get("Ciphers") orelse return 0;
        if (ciphers_val != .array) return 0;

        var count: usize = 0;
        for (ciphers_val.array.items) |cipher_obj| {
            if (cipher_obj != .object) continue;
            const obj = cipher_obj.object;

            const id_val = obj.get("id") orelse obj.get("Id") orelse continue;
            if (id_val != .string) continue;

            const type_val = obj.get("type") orelse obj.get("Type") orelse continue;
            const type_int: u8 = switch (type_val) {
                .integer => |i| @intCast(i),
                else => 1,
            };

            const name_enc = obj.get("name") orelse obj.get("Name") orelse continue;
            if (name_enc != .string) continue;

            const decrypted_name = crypto.decryptCipherString(self.allocator, name_enc.string, keys) catch continue;
            errdefer self.allocator.free(decrypted_name);

            var decrypted_notes: ?[]const u8 = null;
            if (obj.get("notes") orelse obj.get("Notes")) |notes_val| {
                if (notes_val == .string and notes_val.string.len > 0) {
                    decrypted_notes = crypto.decryptCipherString(self.allocator, notes_val.string, keys) catch null;
                }
            }

            var login_data: ?LoginData = null;
            if (obj.get("login") orelse obj.get("Login")) |login_val| {
                if (login_val == .object) {
                    const l_obj = login_val.object;
                    var uri_str: []const u8 = "";
                    var user_str: []const u8 = "";
                    var pass_str: []const u8 = "";
                    var totp_str: ?[]const u8 = null;

                    if (l_obj.get("uris") orelse l_obj.get("Uris")) |uris_val| {
                        if (uris_val == .array and uris_val.array.items.len > 0) {
                            const first_u = uris_val.array.items[0];
                            if (first_u == .object) {
                                if (first_u.object.get("uri") orelse first_u.object.get("Uri")) |u_val| {
                                    if (u_val == .string) {
                                        uri_str = crypto.decryptCipherString(self.allocator, u_val.string, keys) catch try self.allocator.dupe(u8, u_val.string);
                                    }
                                }
                            }
                        }
                    }

                    if (l_obj.get("username") orelse l_obj.get("Username")) |u_val| {
                        if (u_val == .string and u_val.string.len > 0) {
                            user_str = crypto.decryptCipherString(self.allocator, u_val.string, keys) catch try self.allocator.dupe(u8, u_val.string);
                        }
                    }

                    if (l_obj.get("password") orelse l_obj.get("Password")) |p_val| {
                        if (p_val == .string and p_val.string.len > 0) {
                            pass_str = crypto.decryptCipherString(self.allocator, p_val.string, keys) catch try self.allocator.dupe(u8, p_val.string);
                        }
                    }

                    if (l_obj.get("totp") orelse l_obj.get("Totp")) |t_val| {
                        if (t_val == .string and t_val.string.len > 0) {
                            totp_str = crypto.decryptCipherString(self.allocator, t_val.string, keys) catch null;
                        }
                    }

                    login_data = LoginData{
                        .uri = uri_str,
                        .username = user_str,
                        .password = pass_str,
                        .totp = totp_str,
                    };
                }
            }

            try vault.addCipher(.{
                .id = try self.allocator.dupe(u8, id_val.string),
                .cipher_type = @enumFromInt(type_int),
                .name = decrypted_name,
                .notes = decrypted_notes,
                .login = login_data,
                .favorite = false,
            });
            count += 1;
        }

        return count;
    }
};

test "bitwarden sync client build login payload and parse sync response" {
    const allocator = std.testing.allocator;
    var client = BitwardenSyncClient.init(allocator, "https://vault.bitwarden.com");
    defer client.deinit();

    // Verify OAuth2 body generation
    const body = try client.buildLoginRequestBody("user@example.com", "mypasshash123=");
    defer allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "username=user@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "grant_type=password") != null);

    // Set keys
    const master_key = try crypto.deriveMasterKey("Password123!", "user@example.com", 5000);
    const keys = crypto.deriveEncryptionKeys(master_key);

    var vault = Vault.init(allocator);
    defer vault.deinit();
    vault.unlock(keys);

    // Encrypt test fields with real Bitwarden Type 2 CipherStrings
    const enc_name = try crypto.encryptCipherString(allocator, "GitHub Login", &keys);
    defer allocator.free(enc_name);

    const enc_user = try crypto.encryptCipherString(allocator, "octocat", &keys);
    defer allocator.free(enc_user);

    const enc_pass = try crypto.encryptCipherString(allocator, "SuperGitPass999!", &keys);
    defer allocator.free(enc_pass);

    const enc_uri = try crypto.encryptCipherString(allocator, "https://github.com/login", &keys);
    defer allocator.free(enc_uri);

    const sync_json = try std.fmt.allocPrint(
        allocator,
        \\{{
        \\  "ciphers": [
        \\    {{
        \\      "id": "cipher-gh-1",
        \\      "type": 1,
        \\      "name": "{s}",
        \\      "login": {{
        \\        "username": "{s}",
        \\        "password": "{s}",
        \\        "uris": [
        \\          {{ "uri": "{s}" }}
        \\        ]
        \\      }}
        \\    }}
        \\  ]
        \\}}
    ,
        .{ enc_name, enc_user, enc_pass, enc_uri },
    );
    defer allocator.free(sync_json);

    const count = try client.parseAndPopulateVault(sync_json, &keys, &vault);
    try std.testing.expectEqual(@as(usize, 1), count);

    // Verify cipher decrypted into vault
    try std.testing.expectEqual(@as(usize, 1), vault.ciphers.items.len);
    const c0 = &vault.ciphers.items[0];
    try std.testing.expectEqualStrings("GitHub Login", c0.name);
    try std.testing.expect(c0.login != null);
    try std.testing.expectEqualStrings("octocat", c0.login.?.username);
    try std.testing.expectEqualStrings("SuperGitPass999!", c0.login.?.password);
    try std.testing.expectEqualStrings("https://github.com/login", c0.login.?.uri);
}
