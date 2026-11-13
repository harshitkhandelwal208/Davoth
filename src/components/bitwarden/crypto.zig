//! Bitwarden cryptographic operations: PBKDF2, AES-256-CBC, HMAC-SHA256, CipherStrings, and Key Derivation.
const std = @import("std");
const c = @import("../../common/c.zig");

extern "c" fn explicit_bzero(s: *anyopaque, n: usize) void;

pub const DerivedKeys = struct {
    master_key: [32]u8,
    enc_key: [32]u8,
    mac_key: [32]u8,

    pub fn wipe(self: *DerivedKeys) void {
        explicit_bzero(&self.master_key, 32);
        explicit_bzero(&self.enc_key, 32);
        explicit_bzero(&self.mac_key, 32);
    }
};

pub fn secureZero(buf: []u8) void {
    if (buf.len > 0) {
        explicit_bzero(buf.ptr, buf.len);
    }
}

/// Computes PBKDF2(password, email, iterations, SHA-256, 32)
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

/// Computes master password hash for server authentication: PBKDF2(master_key, password, 1, SHA-256, 32)
/// Returned as a Base64 encoded string.
pub fn deriveMasterPasswordHash(allocator: std.mem.Allocator, master_key: [32]u8, password: []const u8) ![]u8 {
    var hash_bytes: [32]u8 = undefined;
    defer secureZero(&hash_bytes);

    const rc = c.PKCS5_PBKDF2_HMAC(
        &master_key,
        32,
        password.ptr,
        @intCast(password.len),
        1,
        c.EVP_sha256(),
        32,
        &hash_bytes,
    );
    if (rc != 1) return error.PasswordHashDerivationFailed;

    const enc = std.base64.standard.Encoder;
    const b64_len = enc.calcSize(hash_bytes.len);
    const out = try allocator.alloc(u8, b64_len);
    _ = enc.encode(out, &hash_bytes);
    return out;
}

/// Derives enc_key and mac_key from master_key using HKDF-Expand with "enc" and "mac" contexts.
pub fn deriveEncryptionKeys(master_key: [32]u8) DerivedKeys {
    var enc_key: [32]u8 = undefined;
    var mac_key: [32]u8 = undefined;

    // RFC 5869 HKDF-Expand: HMAC(PRK, info || 0x01)
    var enc_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&master_key);
    enc_ctx.update("enc\x01");
    enc_ctx.final(&enc_key);

    var mac_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&master_key);
    mac_ctx.update("mac\x01");
    mac_ctx.final(&mac_key);

    return DerivedKeys{
        .master_key = master_key,
        .enc_key = enc_key,
        .mac_key = mac_key,
    };
}

pub const EncryptionType = enum(u8) {
    AesCbc256_B64 = 0,
    AesCbc128_HmacSha256_B64 = 1,
    AesCbc256_HmacSha256_B64 = 2,
    Rsa2048_OaepSha256_B64 = 3,
    Rsa2048_OaepSha1_B64 = 4,
    Rsa2048_OaepSha256_HmacSha256_B64 = 5,
    Rsa2048_OaepSha1_HmacSha256_B64 = 6,
};

pub const CipherString = struct {
    enc_type: EncryptionType,
    iv: []const u8,
    ciphertext: []const u8,
    mac: ?[]const u8,

    pub fn parse(cipher_str: []const u8) !CipherString {
        const dot_pos = std.mem.indexOf(u8, cipher_str, ".") orelse return error.InvalidCipherString;
        const type_num = std.fmt.parseInt(u8, cipher_str[0..dot_pos], 10) catch return error.InvalidCipherStringType;

        const rest = cipher_str[dot_pos + 1 ..];
        var pipe_iter = std.mem.splitScalar(u8, rest, '|');

        const iv = pipe_iter.next() orelse return error.MissingIV;
        const ciphertext = pipe_iter.next() orelse return error.MissingCiphertext;
        const mac = pipe_iter.next();

        return CipherString{
            .enc_type = @enumFromInt(type_num),
            .iv = iv,
            .ciphertext = ciphertext,
            .mac = mac,
        };
    }
};

/// Encrypts raw plaintext with AES-256-CBC and prepends 16-byte random IV.
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
    return try allocator.realloc(ciphertext, total_cipher);
}

/// Decrypts ciphertext where first 16 bytes are IV.
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
    return try allocator.realloc(out_buf, total_plain);
}

/// Encrypts plaintext and produces a standard Bitwarden Type 2 CipherString: "2.<iv_b64>|<ciphertext_b64>|<mac_b64>"
pub fn encryptCipherString(allocator: std.mem.Allocator, plaintext: []const u8, keys: *const DerivedKeys) ![]u8 {
    var iv: [16]u8 = undefined;
    if (c.RAND_bytes(&iv, 16) != 1) return error.RandomGenerationFailed;

    const ctx = c.EVP_CIPHER_CTX_new() orelse return error.CipherCtxAllocFailed;
    defer c.EVP_CIPHER_CTX_free(ctx);

    if (c.EVP_EncryptInit_ex(ctx, c.EVP_aes_256_cbc(), null, &keys.enc_key, &iv) != 1) {
        return error.EncryptInitFailed;
    }

    const raw_ct = try allocator.alloc(u8, plaintext.len + 32);
    defer allocator.free(raw_ct);

    var out_len1: c_int = 0;
    if (c.EVP_EncryptUpdate(ctx, raw_ct.ptr, &out_len1, plaintext.ptr, @intCast(plaintext.len)) != 1) {
        return error.EncryptUpdateFailed;
    }

    var out_len2: c_int = 0;
    const offset1: usize = @intCast(out_len1);
    if (c.EVP_EncryptFinal_ex(ctx, raw_ct.ptr + offset1, &out_len2) != 1) {
        return error.EncryptFinalFailed;
    }
    const ct_len: usize = @intCast(out_len1 + out_len2);
    const ct_slice = raw_ct[0..ct_len];

    // Compute HMAC-SHA256 over iv ++ ciphertext
    var mac_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&keys.mac_key);
    mac_ctx.update(&iv);
    mac_ctx.update(ct_slice);
    var mac_bytes: [32]u8 = undefined;
    mac_ctx.final(&mac_bytes);

    // Base64 encode IV, Ciphertext, and MAC
    const enc = std.base64.standard.Encoder;
    const iv_b64 = try allocator.alloc(u8, enc.calcSize(16));
    defer allocator.free(iv_b64);
    _ = enc.encode(iv_b64, &iv);

    const ct_b64 = try allocator.alloc(u8, enc.calcSize(ct_len));
    defer allocator.free(ct_b64);
    _ = enc.encode(ct_b64, ct_slice);

    const mac_b64 = try allocator.alloc(u8, enc.calcSize(32));
    defer allocator.free(mac_b64);
    _ = enc.encode(mac_b64, &mac_bytes);

    return std.fmt.allocPrint(allocator, "2.{s}|{s}|{s}", .{ iv_b64, ct_b64, mac_b64 });
}

/// Decrypts a Bitwarden CipherString with MAC verification and AES-256-CBC decryption.
pub fn decryptCipherString(allocator: std.mem.Allocator, cipher_str: []const u8, keys: *const DerivedKeys) ![]u8 {
    const cs = try CipherString.parse(cipher_str);
    const dec = std.base64.standard.Decoder;

    const iv_len = try dec.calcSizeForSlice(cs.iv);
    if (iv_len != 16) return error.InvalidIVLength;
    var iv: [16]u8 = undefined;
    try dec.decode(&iv, cs.iv);

    const ct_len = try dec.calcSizeForSlice(cs.ciphertext);
    const ct = try allocator.alloc(u8, ct_len);
    defer allocator.free(ct);
    try dec.decode(ct, cs.ciphertext);

    // Verify MAC if Type 1 or Type 2
    if (cs.enc_type == .AesCbc256_HmacSha256_B64 or cs.enc_type == .AesCbc128_HmacSha256_B64) {
        const mac_str = cs.mac orelse return error.MissingMac;
        const mac_len = try dec.calcSizeForSlice(mac_str);
        if (mac_len != 32) return error.InvalidMacLength;
        var expected_mac: [32]u8 = undefined;
        try dec.decode(&expected_mac, mac_str);

        var mac_ctx: std.crypto.auth.hmac.sha2.HmacSha256 = .init(&keys.mac_key);
        mac_ctx.update(&iv);
        mac_ctx.update(ct);
        var computed_mac: [32]u8 = undefined;
        mac_ctx.final(&computed_mac);

        // Constant-time MAC comparison
        if (!std.crypto.timing_safe.eql([32]u8, computed_mac, expected_mac)) {
            return error.MacVerificationFailed;
        }
    }

    // Decrypt AES-256-CBC
    const ctx = c.EVP_CIPHER_CTX_new() orelse return error.CipherCtxAllocFailed;
    defer c.EVP_CIPHER_CTX_free(ctx);

    if (c.EVP_DecryptInit_ex(ctx, c.EVP_aes_256_cbc(), null, &keys.enc_key, &iv) != 1) {
        return error.DecryptInitFailed;
    }

    const out_buf = try allocator.alloc(u8, ct.len + 16);
    errdefer allocator.free(out_buf);

    var out_len1: c_int = 0;
    if (c.EVP_DecryptUpdate(ctx, out_buf.ptr, &out_len1, ct.ptr, @intCast(ct.len)) != 1) {
        return error.DecryptUpdateFailed;
    }

    var out_len2: c_int = 0;
    const offset1: usize = @intCast(out_len1);
    if (c.EVP_DecryptFinal_ex(ctx, out_buf.ptr + offset1, &out_len2) != 1) {
        return error.DecryptFinalFailed;
    }

    const total_plain = @as(usize, @intCast(out_len1 + out_len2));
    return try allocator.realloc(out_buf, total_plain);
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

test "bitwarden authenticated cipherstring encryption, MAC verification and decryption" {
    const allocator = std.testing.allocator;
    const master_key = try deriveMasterKey("VaultMasterPassword456$", "test@davoth.org", 6000);
    const keys = deriveEncryptionKeys(master_key);

    // Test master password hash derivation
    const pwd_hash = try deriveMasterPasswordHash(allocator, master_key, "VaultMasterPassword456$");
    defer allocator.free(pwd_hash);
    try std.testing.expect(pwd_hash.len > 0);

    // Test Type 2 authenticated encryption
    const secret_note = "High Security API Key: sk_live_9876543210Davoth";
    const cipher_str = try encryptCipherString(allocator, secret_note, &keys);
    defer allocator.free(cipher_str);

    // Verify format "2.<iv>|<ciphertext>|<mac>"
    try std.testing.expect(std.mem.startsWith(u8, cipher_str, "2."));

    // Decrypt and verify
    const decrypted_note = try decryptCipherString(allocator, cipher_str, &keys);
    defer allocator.free(decrypted_note);
    try std.testing.expectEqualStrings(secret_note, decrypted_note);

    // Verify MAC tampering is rejected
    var tampered = try allocator.dupe(u8, cipher_str);
    defer allocator.free(tampered);
    const last_char = tampered[tampered.len - 2];
    tampered[tampered.len - 2] = if (last_char == 'A') 'B' else 'A';
    try std.testing.expectError(error.MacVerificationFailed, decryptCipherString(allocator, tampered, &keys));
}
