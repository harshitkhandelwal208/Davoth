//! Bitwarden cryptographic operations: PBKDF2, AES-256-CBC, HMAC-SHA256, and Password Generator.
const std = @import("std");
const c = @import("../../common/c.zig");

pub const DerivedKeys = struct {
    master_key: [32]u8,
    enc_key: [32]u8,
    mac_key: [32]u8,
};

pub fn deriveMasterKey(password: []const u8, email: []const u8, iterations: u32) ![32]u8 {
    var key: [32]u8 = undefined;
    const rc = c.PKCS5_PBKDF2_HMAC(
        password.ptr,
        @intCast(password.len),
        email.ptr,
        @intCast(email.len),
        @intCast(iterations),
        c.EVP_sha256(),
        32,
        &key,
    );
    if (rc != 1) return error.KeyDerivationFailed;
    return key;
}

pub fn deriveEncryptionKeys(master_key: [32]u8) DerivedKeys {
    // HKDF-Expand with "enc" and "mac" contexts per Bitwarden specification
    var enc_key: [32]u8 = undefined;
    var mac_key: [32]u8 = undefined;

    // Use SHA-256 HMAC of master_key with info tag
    var enc_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&master_key);
    enc_ctx.update("enc");
    enc_ctx.final(&enc_key);

    var mac_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&master_key);
    mac_ctx.update("mac");
    mac_ctx.final(&mac_key);

    return DerivedKeys{
        .master_key = master_key,
        .enc_key = enc_key,
        .mac_key = mac_key,
    };
}

pub fn encryptAes256Cbc(allocator: std.mem.Allocator, plaintext: []const u8, key: [32]u8) ![]u8 {
    var iv: [16]u8 = undefined;
    if (c.RAND_bytes(&iv, 16) != 1) return error.RandomGenerationFailed;

    const ctx = c.EVP_CIPHER_CTX_new() orelse return error.CipherCtxAllocFailed;
    defer c.EVP_CIPHER_CTX_free(ctx);

    if (c.EVP_EncryptInit_ex(ctx, c.EVP_aes_256_cbc(), null, &key, &iv) != 1) {
        return error.EncryptInitFailed;
    }

    const max_len = plaintext.len + 32;
    const ciphertext = try allocator.alloc(u8, 16 + max_len);
    errdefer allocator.free(ciphertext);

    @memcpy(ciphertext[0..16], &iv);

    var out_len1: c_int = 0;
    if (c.EVP_EncryptUpdate(ctx, ciphertext.ptr + 16, &out_len1, plaintext.ptr, @intCast(plaintext.len)) != 1) {
        return error.EncryptUpdateFailed;
    }

    var out_len2: c_int = 0;
    const offset1: usize = @intCast(out_len1);
    if (c.EVP_EncryptFinal_ex(ctx, ciphertext.ptr + 16 + offset1, &out_len2) != 1) {
        return error.EncryptFinalFailed;
    }

    const total_cipher = 16 + @as(usize, @intCast(out_len1 + out_len2));
    return ciphertext[0..total_cipher];
}

pub fn decryptAes256Cbc(allocator: std.mem.Allocator, ciphertext_with_iv: []const u8, key: [32]u8) ![]u8 {
    if (ciphertext_with_iv.len < 16) return error.CiphertextTooShort;

    const iv = ciphertext_with_iv[0..16];
    const encrypted = ciphertext_with_iv[16..];

    const ctx = c.EVP_CIPHER_CTX_new() orelse return error.CipherCtxAllocFailed;
    defer c.EVP_CIPHER_CTX_free(ctx);

    if (c.EVP_DecryptInit_ex(ctx, c.EVP_aes_256_cbc(), null, &key, iv.ptr) != 1) {
        return error.DecryptInitFailed;
    }

    const out_buf = try allocator.alloc(u8, encrypted.len + 16);
    errdefer allocator.free(out_buf);

    var out_len1: c_int = 0;
    if (c.EVP_DecryptUpdate(ctx, out_buf.ptr, &out_len1, encrypted.ptr, @intCast(encrypted.len)) != 1) {
        return error.DecryptUpdateFailed;
    }

    var out_len2: c_int = 0;
    const offset1: usize = @intCast(out_len1);
    if (c.EVP_DecryptFinal_ex(ctx, out_buf.ptr + offset1, &out_len2) != 1) {
        return error.DecryptFinalFailed;
    }

    const total_plain = @as(usize, @intCast(out_len1 + out_len2));
    return out_buf[0..total_plain];
}

pub fn generatePassword(allocator: std.mem.Allocator, length: usize, uppercase: bool, lowercase: bool, numbers: bool, special: bool) ![]u8 {
    var charset: std.ArrayList(u8) = .empty;
    defer charset.deinit(allocator);

    if (uppercase) try charset.appendSlice(allocator, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (lowercase) try charset.appendSlice(allocator, "abcdefghijklmnopqrstuvwxyz");
    if (numbers) try charset.appendSlice(allocator, "0123456789");
    if (special) try charset.appendSlice(allocator, "!@#$%^&*()-_=+[]{}|;:,.<>?");

    if (charset.items.len == 0) return error.EmptyCharset;

    const pwd = try allocator.alloc(u8, length);
    errdefer allocator.free(pwd);

    var rand_buf: [256]u8 = undefined;
    var cursor: usize = 0;
    while (cursor < length) {
        const batch = @min(length - cursor, rand_buf.len);
        if (c.RAND_bytes(&rand_buf, @intCast(batch)) != 1) {
            return error.RandomGenerationFailed;
        }
        for (rand_buf[0..batch]) |b| {
            pwd[cursor] = charset.items[b % charset.items.len];
            cursor += 1;
        }
    }

    return pwd;
}

test "bitwarden crypto key derivation, encrypt, decrypt and password generator" {
    const allocator = std.testing.allocator;
    const master_key = try deriveMasterKey("SuperSecretPassword123!", "user@davoth.org", 5000);
    const keys = deriveEncryptionKeys(master_key);

    const secret_data = "DavothBrowserVaultSecretCredentialToken";
    const encrypted = try encryptAes256Cbc(allocator, secret_data, keys.enc_key);
    defer allocator.free(encrypted);

    const decrypted = try decryptAes256Cbc(allocator, encrypted, keys.enc_key);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(secret_data, decrypted);

    const generated = try generatePassword(allocator, 16, true, true, true, true);
    defer allocator.free(generated);
    try std.testing.expectEqual(@as(usize, 16), generated.len);
}
