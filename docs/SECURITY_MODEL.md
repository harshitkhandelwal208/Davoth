# Davoth Browser — Security Model Specification

Security is foundational to Davoth's design. This document specifies the browser's security boundaries, isolation model, web standards enforcement, and cryptographic implementations.

---

## 1. Same-Origin Policy (SOP)

The Same-Origin Policy is enforced at the core of all DOM access, storage, cookie partitioning, and network requests (`src/security/origin.zig`).

### Origin Tuple
An Origin is defined as a 3-tuple:
$$\text{Origin} = (\text{Scheme}, \text{Host}, \text{Port})$$

Two origins $A$ and $B$ are identical if and only if:
- $A.\text{scheme} = B.\text{scheme}$ (case-insensitive)
- $A.\text{host} = B.\text{host}$ (case-insensitive)
- $A.\text{port} = B.\text{port}$ (default ports: HTTP = 80, HTTPS = 443)

### Opaque Origins
Unique, non-serializable origins (`is_opaque = true`) are assigned to:
- Sandboxed `<iframe>` elements without `allow-same-origin`.
- `data:` URLs.
- Failed redirects and cross-origin worker initializations.
- Opaque origins never match any other origin, even another opaque origin.

---

## 2. Cross-Origin Resource Sharing (CORS)

Cross-origin HTTP requests are gated by the CORS engine (`src/security/cors.zig`):

1. **Simple Requests:**
   - Methods: `GET`, `HEAD`, `POST`.
   - Headers: `Accept`, `Accept-Language`, `Content-Language`, `Content-Type` (only `application/x-www-form-urlencoded`, `multipart/form-data`, `text/plain`).
   - Direct dispatch with `Origin` request header. Response must include matching `Access-Control-Allow-Origin` (`*` or exact origin).
2. **Preflight Requests:**
   - Any request with custom methods (`PUT`, `DELETE`, `PATCH`) or custom headers triggers an `OPTIONS` preflight.
   - The browser validates:
     - `Access-Control-Allow-Origin`
     - `Access-Control-Allow-Methods`
     - `Access-Control-Allow-Headers`
     - `Access-Control-Allow-Credentials` (when credentials mode is `include`, wildcard `*` is forbidden).

---

## 3. Content Security Policy (CSP)

Davoth parses and enforces CSP Level 3 directives (`src/security/csp.zig`):

| Directive | Scope |
| :--- | :--- |
| `default-src` | Fallback policy for all resource types |
| `script-src` | JavaScript execution, `<script>` tags, workers |
| `style-src` | CSS stylesheets and `<style>` blocks |
| `img-src` | Image sources and favicons |
| `connect-src` | `fetch()`, `XMLHttpRequest`, WebSockets, EventSource |
| `font-src` | Web fonts (`@font-face`) |
| `object-src` | Plugins (disabled by default) |
| `frame-src` | Child browsing contexts and `<iframe>` embeds |

### Keyword & Nonce Enforcement
- `'none'`: Blocks all resources.
- `'self'`: Matches the document's origin.
- Nonce verification: Script tags must provide a cryptographic nonce matching `nonce-...` in the directive header.
- Dynamic code evaluation (`eval()`, `new Function()`) is blocked unless `'unsafe-eval'` is explicitly specified.

---

## 4. Multi-Process Sandboxing & Site Isolation (`src/security/sandbox.zig`)

Davoth employs a multiprocess architecture separating untrusted web content from the privileged UI and system resources:

```
[ UI / Browser Shell Process ] (Host Access: Display, Disk, Network Daemon)
          |
          | Pipe / Socket IPC (`src/common/ipc.zig`)
          v
[ Isolated Render Process ] (Sandboxed)
  - HTML Tokenizer & DOM
  - CSS Cascade & Layout Engine
  - JavaScript Engine & WASM Runtime
  - CPU Rasterizer / Vulkan Command Buffers
```

### Linux Sandbox Boundaries
1. **Namespaces:** Render processes are spawned in isolated User (`CLONE_NEWUSER`), Mount (`CLONE_NEWNS`), PID (`CLONE_NEWPID`), and Network (`CLONE_NEWNET`) namespaces.
2. **Filesystem:** Render processes have no write access to user files. Local file read is restricted to explicit file descriptor passing from the UI process.
3. **Seccomp-BPF Syscall Filtering:**
   - Kernel system calls permitted: `read`, `write`, `mmap`, `munmap`, `mprotect`, `futex`, `sched_yield`, `exit_group`.
   - Forbidden system calls: `socket`, `connect`, `open`, `execve`, `fork`, `kill`, `ptrace`. Attempts immediately terminate the process with `SIGSYS`.

---

## 5. TLS 1.3 & Certificate Validation (`src/security/certs.zig`)

1. **Protocol Minimum:** Modern TLS 1.2 and TLS 1.3 are supported. SSL 2.0, SSL 3.0, and TLS 1.0/1.1 are permanently disabled.
2. **ALPN (Application-Layer Protocol Negotiation):** Transparently negotiates `h2` (HTTP/2) and `http/1.1`.
3. **System Trust Store:** Validates peer certificates against `/etc/ssl/certs/ca-certificates.crt`. Self-signed or expired certificates fail with strict certificate error warnings.

---

## 6. Bitwarden Cryptographic Security Model (`src/components/bitwarden/crypto.zig`)

The Bitwarden password manager integration adheres strictly to upstream Bitwarden cryptographic specifications:

1. **Key Derivation (PBKDF2):**
   - PBKDF2-HMAC-SHA256 with user-configured iterations (default: 600,000 iterations).
   - Generates the Master Key used to decrypt the vault key.
2. **Symmetric Encryption (AES-256-CBC):**
   - Vault items, usernames, passwords, notes, and URIs are encrypted using 256-bit AES in Cipher Block Chaining (CBC) mode with PKCS#7 padding.
   - Every cipher entry generates a random 16-byte Initialization Vector (IV) prepended to the ciphertext.
3. **Zero-Knowledge Architecture:**
   - Plaintext credentials and master keys never touch persistent disk storage.
   - Master keys are held only in locked memory pages while the vault is unlocked, and zeroed immediately upon locking.
