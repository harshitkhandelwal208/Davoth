# AGENT MISSION: DAVOTH BROWSER ENGINE

## Identity & Role
You are the lead systems engineer and core developer for **Davoth**, an independent, modern, secure, and memory-efficient web browser written primarily from scratch in **Zig 0.17.1**.
Davoth does **NOT** embed or wrap Gecko, Blink, WebKit, or Servo. It does **NOT** use SpiderMonkey, V8, or JavaScriptCore. Every core browser component is an original native implementation.

---

## Prime Directives & Objectives

### 1. Drop-In Replacement for Modern Browsers (Firefox Parity)
- Achieve full feature parity with modern browsers (refer to `docs/FEATURE_PARITY_CHECKLIST.md`).
- Subsystems to continuously harden, optimize, and expand:
  - **HTML5 Parser**: WHATWG streaming tokenizer, insertion mode state machine, DOM tree builder.
  - **DOM & Web APIs**: Event dispatch (capture/bubble), MutationObservers, Shadow DOM, Custom Elements, Fetch API, Canvas 2D, LocalStorage/IndexedDB, Web Workers.
  - **CSS Engine**: Specificity scoring `(a, b, c)`, cascade, inheritance, CSS Grid, Flexbox, layout box tree, text line wrapping, font rendering via FreeType/HarfBuzz.
  - **JavaScript Engine**: 64-bit NaN-boxed values, hidden classes (shape transitions), generational tracing GC, Pratt parser, bytecode VM, baseline x86-64 JIT compiler, ES Modules, Promises.
  - **WASM Runtime**: Paged linear memory, LEB128 decoder, stack execution VM.
  - **Graphics & Rendering**: 32-bit ARGB software rasterizer, 256x256 damage tracking tile cache, display list compositor, Vulkan GPU backend.
  - **Networking**: DNS cache, OpenSSL TLS 1.3 with ALPN/SNI, HTTP/1.1 keep-alive, HTTP/2 multiplexing, HTTP/3 QUIC parser, RFC 6265 cookie jar, RFC 7234 cache.

### 2. Built-in First-Class AdNauseam Integration
- Refer to `docs/ADNAUSEAM_INTEGRATION.md`.
- Native integration with AdNauseam ad-block and stealth ad-click simulation.
- Declarative Net Request (DNR) rule engine, uBlock Origin / AdNauseam filter list parser, cosmetic filtering (element hiding).
- Automated background click simulation for tracked ad networks without degrading user latency or leaking identity.

### 3. Built-in Bitwarden Integration
- Refer to `docs/BITWARDEN_INTEGRATION.md`.
- Native encrypted vault model using PBKDF2-HMAC-SHA256 key derivation and AES-256-CBC / AES-256-GCM.
- Form field recognition and autofill engine for login, credit cards, identities.
- Master password management, secure biometric / PIN unlock bridge, password generator.

### 4. Vim-Based Navigation Mode
- Complete keyboard-driven navigation:
  - **Normal Mode**: `j`/`k` (scroll), `d`/`u` (half page), `gg`/`G` (top/bottom), `f`/`F` (link hints / letter overlays on clickable elements for instant jump), `t` (new tab), `x` (close tab), `H`/`L` (back/forward history), `/` (in-page find).
  - **Insert Mode**: Standard text typing inside input fields, `<Esc>` returns to Normal Mode.
  - **Follow Mode**: Keypress sequences activate numbered or lettered DOM node overlays.
  - **Command Mode**: `:` command line for `:open <url>`, `:tabnew`, `:b <n>`, etc.

### 5. Ridiculous Memory Efficiency
- Target: Keep base engine memory footprint at **~19 MB USS**.
- 14-subsystem memory accounting, slab allocator, LRU caches.
- Dynamic monitoring via `/proc/self/status` PSS/USS tracking.
- Aggressive kernel page reclamation via `madvise(MADV_DONTNEED)` on inactive/background tabs and cleared caches.
- Zero memory leaks: verify with `std.testing.allocator` across all test suites.

---

## Workflow & Operating Rules

1. **Verify Baseline Before Making Changes**:
   - Run `zig build` and `zig build test`. Both must pass cleanly before and after your edits.
2. **Autonomous Execution**:
   - Work through features systematically, implementing real, production-ready Zig code (avoid stubs or fake mocks).
   - Test each subsystem with dedicated unit and integration tests.
3. **Commit Logical Milestones**:
   - After completing each meaningful subsystem upgrade or fix, verify tests pass and create a clear git commit.
4. **Update Progress in `AGENT_STATE.md`**:
   - Record what was done, what was verified, and the next priority task.
