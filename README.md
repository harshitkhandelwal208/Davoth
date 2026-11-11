# DAVOTH

> **A completely independent, modern, secure, feature-rich and memory-efficient web browser written primarily from scratch in Zig 0.17.1.**

Davoth is a genuine alternative to Firefox. It does **NOT** embed or wrap Gecko, Blink, WebKit or Servo. It does **NOT** use SpiderMonkey, V8 or JavaScriptCore. Every core browser component is an original native implementation.

---

## Key Highlights

- **100% Independent Engine:** JavaScript engine, WASM runtime, HTML parser, DOM tree, CSS cascade, layout engine, software rasterizer, compositor, and networking stack built natively in Zig 0.17.1.
- **Firefox WebExtensions Compatibility:** Full native support for Firefox WebExtensions (Manifest V2 and V3, `browser.webRequest`, `browser.storage`, `browser.tabs`, `browser.runtime`, isolated content scripts).
- **First-Class AdNauseam Integration:** Native integration with `dhowe/AdNauseam` (release 3.29.2) including stealth ad click simulation and automated upstream update detection.
- **Bitwarden-Based Password Manager:** Native vault model, PBKDF2-HMAC-SHA256 key derivation, AES-256-CBC encryption, password generator, form autofill, and upstream client tracking (`bitwarden/clients`).
- **Memory Efficiency:** 14-subsystem memory accounting, slab allocator, LRU caches, `/proc/self/status` PSS/USS tracking, and kernel page reclamation via `madvise(MADV_DONTNEED)`. Base engine runs in **~19 MB USS**.
- **Firefox Feature Parity:** Multi-account container tabs, pinned tabs, tab groups, smart URL bar, reader mode, PDF viewer, picture-in-picture, full page screenshot capture, Vim navigation mode, and encrypted cross-device sync.
- **Multiprocess Security Architecture:** Linux namespace isolation (User, Mount, PID, Net), seccomp-bpf syscall filtering, Same-Origin Policy (SOP), CORS, and Content Security Policy (CSP).

---

## Subsystem Architecture

| Directory | Subsystem | Description |
| :--- | :--- | :--- |
| `src/common/` | Core Infrastructure | Geometric types, thread-safe string interning (`AtomTable`), RFC 3986 URL parser, multiprocess IPC channel, memory accounting, libc ABI bridge |
| `src/js/` | JavaScript Engine | 64-bit NaN-boxed values, shape transition trees (hidden classes), generational tracing GC, Pratt parser, bytecode VM, baseline x86-64 JIT compiler, Promises, ES modules |
| `src/wasm/` | WebAssembly Runtime | Binary decoder, LEB128 parser, section validator, 64KB paged linear memory, stack execution VM |
| `src/html/` | HTML5 Parser | WHATWG streaming tokenizer, insertion mode state machine, tree builder |
| `src/dom/` | Document Object Model | DOM Core nodes, 3-phase event dispatch (capture, at-target, bubble), mutation observers, Shadow DOM and Custom Elements |
| `src/css/` | CSS Engine | Lexer, parser, selector matching with `(a, b, c)` specificity scoring, style cascade, inheritance |
| `src/layout/` | Layout Engine | Box model (`Dimensions`), block formatting context, Flexbox layout, CSS Grid layout, text line wrapping, spatial hit testing |
| `src/rendering/` | Retained Rendering | Retained display list items, stacking contexts, 256x256 damage tracking tile cache, compositor |
| `src/graphics/` | Graphics Backends | High-performance 32-bit ARGB CPU software rasterizer with alpha blending and PPM export, Vulkan GPU backend |
| `src/net/` | Networking Stack | DNS resolver with TTL caching, OpenSSL TLS 1.3 with ALPN and SNI, HTTP/1.1 keep-alive client, HTTP/2 framing, HTTP/3 QUIC parser, RFC 6265 cookie jar, RFC 7234 cache |
| `src/webapis/` | Web Standards APIs | Fetch API, XMLHttpRequest, LocalStorage, SessionStorage, HTML5 Canvas 2D context, IndexedDB, Web Workers, HTMLMediaElement |
| `src/media/` | Media Decoders | BMP and PNG image decoders, FreeType font loader, HarfBuzz text shaping bridge, audio playback stream |
| `src/storage/` | Persistent Storage | SQLite3 database engine, history with frecency scoring, hierarchical bookmarks, session restore database, user preferences |
| `src/security/` | Security & Sandboxing | Same-Origin Policy (SOP), CORS preflight validator, CSP Level 3 policy engine, Linux namespaces and seccomp-bpf sandbox, certificate validation, permissions broker |
| `src/accessibility/` | Accessibility | Accessible tree hierarchy, keyboard focus manager, Linux AT-SPI bridge |
| `src/devtools/` | Developer Tools | DOM inspector, CSS live style inspector, network timeline inspector, subsystem memory profiler |
| `src/ui/` | Browser Shell & UI | Multi-account container tabs, pinned tabs, smart URL bar, reader mode, PDF viewer, PiP video, page capture, Vim modal navigation, GTK4 desktop application |
| `src/extensions/` | WebExtensions | Manifest V2/V3 parser, XPI container extractor, content script injector, WebRequest API, DNR rule engine, Tabs API, Storage API, Runtime API |
| `src/components/bitwarden/` | Bitwarden Integration | Native vault model, PBKDF2 / AES-256-CBC crypto, password generator, form autofill, Bitwarden API sync |
| `src/tools/` | Automated Updaters | Upstream update detection and checksum validation for AdNauseam and Bitwarden |

---

## Building and Testing

### Prerequisites
- Linux x86_64
- Zig 0.17.1
- System libraries: `sqlite3`, `ssl`, `crypto`, `freetype2`, `harfbuzz`, `vulkan`, `gtk-4`, `glib-2.0`, `gobject-2.0`, `gio-2.0`

### Build Executable
```bash
zig build
```
The compiled binary will be placed at `./zig-out/bin/davoth`.

### Run Automated Test Suite
```bash
zig build test --summary all
```

---

## Command-Line Usage

```bash
# Display help and command options
./zig-out/bin/davoth --help

# Show engine version and platform details
./zig-out/bin/davoth --version

# Evaluate JavaScript with Davoth's original JS engine
./zig-out/bin/davoth --eval-js "let a = 10; let b = 32; return a + b;"
# Output: JS Result: 42 (type: Float64)

# Parse and dump HTML5 DOM tree structure
./zig-out/bin/davoth --dump-dom about:home

# Render a page and capture viewport to a 24-bit PPM image
./zig-out/bin/davoth --render about:home --screenshot /tmp/davoth_home.ppm

# Run native Bitwarden vault crypto, PBKDF2, and autofill verification
./zig-out/bin/davoth --test-bitwarden

# Run AdNauseam WebExtensions compatibility and WebRequest filtering verification
./zig-out/bin/davoth --test-adnauseam

# Run per-subsystem memory accounting benchmarks
./zig-out/bin/davoth --bench-memory

# Launch browser (GTK4 desktop window when display is available, or headless display)
./zig-out/bin/davoth [url]
```

---

## Documentation

Detailed technical documentation is available in the [`docs/`](docs/) directory:
- [Firefox Feature Parity Checklist](docs/FEATURE_PARITY_CHECKLIST.md)
- [Engine Architecture Specification](docs/ARCHITECTURE.md)
- [Security Model & Sandboxing](docs/SECURITY_MODEL.md)
- [WebExtensions Compatibility](docs/WEBEXTENSIONS.md)
- [AdNauseam Integration Architecture](docs/ADNAUSEAM_INTEGRATION.md)
- [Bitwarden Password Manager Integration](docs/BITWARDEN_INTEGRATION.md)
- [Memory & Performance Benchmarks](docs/BENCHMARKS.md)

---

## License

Davoth is licensed under the GNU General Public License v3.0. See individual subsystem files for upstream attribution details for AdNauseam and Bitwarden components.
