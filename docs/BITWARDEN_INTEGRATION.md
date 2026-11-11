# Davoth Browser — Bitwarden Password Manager Integration

Davoth integrates a fully functional native password manager based directly on the official **Bitwarden** architecture.

- **Upstream Repository:** `https://github.com/bitwarden/clients`
- **Integrated Upstream Release:** `dist-firefox-2026.10.2.zip`
- **License:** GNU General Public License v3.0 (preserved in `src/components/bitwarden/LICENSE`)

---

## 1. Architectural Philosophy

Rather than building a proprietary or siloed password manager, Davoth adopts the Bitwarden open standard. This allows users to manage their vaults locally, generate strong passwords, autofill login forms seamlessly, and synchronize securely with Bitwarden-compatible backends (including official Bitwarden servers and self-hosted Vaultwarden instances).

```
+-------------------------------------------------------------------------------+
|                       BITWARDEN SUBSYSTEM ARCHITECTURE                        |
+-------------------------------------------------------------------------------+
|                                                                               |
|   [ Upstream Package: src/components/bitwarden/upstream/bitwarden-firefox.zip]|
|                                     |                                         |
|                                     v                                         |
|                 [ Native Bitwarden Vault (`vault.zig`) ]                      |
|                                     |                                         |
|               +---------------------+---------------------+                   |
|               |                                           |                   |
|               v                                           v                   |
|   [ OpenSSL Crypto Engine ]                  [ DOM Form Autofill Engine ]     |
|   - PBKDF2-HMAC-SHA256 key derivation        - Detects <input type="password">|
|   - AES-256-CBC encryption/decryption        - Matches document origin to URI |
|   - 16-byte cryptographically random IV      - Fills username & credentials   |
|   - Secure memory zeroing upon vault lock    - User consent gating            |
|                                                                               |
|                                     |                                         |
|                                     v                                         |
|             [ Automated Upstream Updater (updater.zig) ]                      |
|             - Polls GitHub releases for bitwarden/clients                     |
|             - Validates SHA-256 hashes                                        |
|             - Executes automated vault encryption regression tests            |
+-------------------------------------------------------------------------------+
```

---

## 2. Cryptographic Implementation (`src/components/bitwarden/crypto.zig`)

All cryptographic operations leverage OpenSSL via direct, hardened C ABI bindings:

1. **PBKDF2-HMAC-SHA256 Key Derivation:**
   ```zig
   pub fn deriveMasterKey(allocator: std.mem.Allocator, password: []const u8, email: []const u8, iterations: u32) ![32]u8
   ```
   Derives a 256-bit symmetric master key from user master password and normalized email salt using 600,000 iterations.
2. **AES-256-CBC Encryption & Decryption:**
   ```zig
   pub fn encryptAes256Cbc(allocator: std.mem.Allocator, plaintext: []const u8, key: [32]u8) ![]u8
   pub fn decryptAes256Cbc(allocator: std.mem.Allocator, ciphertext_with_iv: []const u8, key: [32]u8) ![]u8
   ```
   Uses standard Cipher Block Chaining with PKCS#7 padding. Every encryption operation generates a unique 16-byte random IV from `/dev/urandom` that is prepended to the ciphertext.
3. **Password Generator:**
   Generates cryptographically random passwords with user-configurable parameters:
   - Length (8 to 128 characters).
   - Uppercase letters (`A-Z`).
   - Lowercase letters (`a-z`).
   - Digits (`0-9`).
   - Special characters (`!@#$%^&*()-_=+[]{}|;:,.<>?`).

---

## 3. DOM Form Autofill Engine (`src/components/bitwarden/autofill.zig`)

When a webpage loads:
1. `AutofillEngine.findCredentialsForUrl()` queries the unlocked vault for ciphers matching the active tab's origin tuple.
2. The DOM tree is scanned for `<form>` elements containing `<input type="password">` and associated username / email fields.
3. Form fields are autofilled without exposing plaintext passwords to unprivileged page scripts.
4. Submission of new or updated credentials triggers a prompt to save or update the item in the vault.

---

## 4. Automated Upstream Update Infrastructure (`src/tools/bitwarden_updater/updater.zig`)

Davoth tracks upstream Bitwarden releases automatically:

```bash
# Automated check for upstream Bitwarden releases
davoth --test-bitwarden
```

The updater tool performs:
1. **GitHub Release Tracking:** Monitors `https://api.github.com/repos/bitwarden/clients/releases/latest`.
2. **Package Verification:** Verifies release signatures and SHA-256 digests.
3. **Controlled Patch Application:** Tests compatibility before staging updates into `src/components/bitwarden/`.
4. **Security Invariant:** Never weakens cryptographic algorithms or bypasses encryption for convenience.

---

## 5. Automated Verification

Execute the built-in Bitwarden verification suite with:

```bash
./zig-out/bin/davoth --test-bitwarden
```

Output:
```
Running Bitwarden integration verification...
Bitwarden AES-256-CBC Encryption/Decryption: OK
Bitwarden PBKDF2-HMAC-SHA256 Derivation: OK
Bitwarden Password Generator (24 chars): }^}(}P7ljC#I[r#X)IBE[>o,
Bitwarden Vault Store & Form Match: OK
```
