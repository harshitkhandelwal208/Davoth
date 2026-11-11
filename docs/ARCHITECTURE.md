# Davoth Browser — Engine Architecture Specification

Davoth is an independent, modern web browser built from scratch in **Zig 0.17.1**. It does not embed or fork Gecko, Blink, WebKit, Servo, SpiderMonkey, V8, or JavaScriptCore. Every core component—from the JavaScript virtual machine to the HTML tokenizer, CSS cascade, layout engine, software rasterizer, and network stack—is an original native implementation.

```
+-----------------------------------------------------------------------------------------+
|                                    DAVOTH BROWSER                                      |
+-----------------------------------------------------------------------------------------+
|                                  Browser Shell (UI)                                     |
|  - Tabs & Containers      - Smart URL Bar          - Vim Navigation Mode                |
|  - History & Bookmarks    - Bitwarden Vault UI     - Extension Manager                  |
+-----------------------------------------------------------------------------------------+
|                                Multi-Process IPC Channel                                |
|  - UI Process             - Render Process         - Network Process    - GPU Process   |
+-----------------------------------------------------------------------------------------+
|     HTML5 / DOM Pipeline     |    CSS / Style Engine     |   JavaScript & WASM Runtime  |
|  - Streaming Tokenizer       |  - CSS Lexer & Parser     |  - NaN-Boxed 64-bit Values   |
|  - Tree Builder (WHATWG)     |  - Selector Matching      |  - Hidden Classes (Shapes)   |
|  - DOM Core & Event Dispatch |  - Specificity (a, b, c)  |  - Generational Tracing GC   |
|  - Shadow DOM & Components   |  - Computed Style Cascade |  - Bytecode VM & Baseline JIT|
|  - Mutation Observers        |  - Inheritance Engine     |  - ES Modules & Promises     |
|                              |                           |  - WASM Linear Memory & VM   |
+-----------------------------------------------------------------------------------------+
|                                   Layout Engine                                         |
|  - Layout Tree Constructor   - Block Formatting Context  - Flexbox Layout Algorithm     |
|  - CSS Grid Layout           - Text Measurement & Wrap   - Hit Testing & Spatial Query  |
+-----------------------------------------------------------------------------------------+
|                                Rendering & Compositor                                   |
|  - Retained Display List     - Stacking Contexts / Scene - Damage Rect Tile Cache       |
|  - CPU Software Rasterizer   - Vulkan GPU Backend        - Multi-layer Compositor       |
+-----------------------------------------------------------------------------------------+
|                                  Networking Stack                                       |
|  - DNS Resolver & Caching    - OpenSSL TLS 1.3 & ALPN    - HTTP/1.1 Keep-Alive Client   |
|  - HTTP/2 Frame Multiplexing - HTTP/3 QUIC Framing       - RFC 6265 Cookie Jar & Cache  |
+-----------------------------------------------------------------------------------------+
|                                Memory & OS Isolation                                    |
|  - 14 Subsystem Accounting   - Slab & Arena Allocators   - RSS / PSS / USS Tracking     |
|  - Linux Namespace Sandbox   - Seccomp-BPF Syscall Filter- madvise(MADV_DONTNEED) Free  |
+-----------------------------------------------------------------------------------------+
```

---

## 1. JavaScript Engine (`src/js/`)

Davoth implements an original ECMAScript-compliant JavaScript virtual machine with high-performance memory design:

1. **64-bit NaN-Boxed Values (`value.zig`):**
   - All JS values (`JSValue`) fit inside a single 64-bit word (`u64`) using IEEE 754 quiet NaN quiet payloads.
   - Pointers to heap objects, 32-bit signed integers, booleans, undefined, null, atom strings, and symbols are represented without heap allocation.
2. **Hidden Classes / Shapes (`object.zig`):**
   - Objects transition along a shape tree when properties are added.
   - Properties are stored in flat array indexed slots for $O(1)$ fast lookups without hash map overhead.
   - Supports prototype chain inheritance and accessor descriptors.
3. **Generational Tracing Garbage Collector (`gc.zig`):**
   - Precise mark-and-sweep tracing collector.
   - Objects are allocated in GC pools with mark bits and cycle detection.
   - Root registry protects active interpreter frames, global environment, and registered DOM wrappers.
4. **Lexer & Pratt Parser (`lexer.zig`, `parser.zig`):**
   - Lexical analyzer handles tokens, keyword recognition, template literals, and regex literals.
   - Pratt operator precedence parser produces a lightweight AST without recursion hazards.
5. **Bytecode Compiler & Stack Virtual Machine (`bytecode.zig`, `interpreter.zig`):**
   - Emits compact bytecode instructions (`OpCode`).
   - Call frames maintain local variable registers and instruction pointers.
6. **Baseline JIT Compiler (`jit.zig`):**
   - Native x86-64 machine code generator emitting binary instructions into executable pages allocated via `mmap(PROT_READ | PROT_WRITE | PROT_EXEC)`.
7. **Promises & Microtask Queue (`promise.zig`):**
   - Full Promise lifecycle (`Pending`, `Fulfilled`, `Rejected`) with microtask reaction queuing.
8. **ES Modules (`modules.zig`):**
   - Module record loader supporting named exports, default exports, and import bindings.

---

## 2. WebAssembly Runtime (`src/wasm/`)

- Binary WASM module decoder reading WASM header, type section, function section, memory section, export section, and code section.
- Bytecode operand stack validator checking type constraints prior to execution.
- 64KB paged linear memory with strict out-of-bounds validation.
- Stack-based virtual execution engine executing WASM instructions.

---

## 3. HTML5 & DOM Engine (`src/html/`, `src/dom/`)

- **Streaming Tokenizer:** WHATWG HTML5 compliant state machine converting raw UTF-8 octets into element tags, attributes, text, and comments.
- **Tree Builder:** Insertion mode stack (`Initial`, `BeforeHtml`, `BeforeHead`, `InHead`, `AfterHead`, `InBody`, `AfterBody`) generating compliant DOM hierarchies.
- **DOM Core (`src/dom/node.zig`):** Intrusive tree pointers (`first_child`, `last_child`, `next_sibling`, `previous_sibling`, `parent_node`) ensuring zero allocation for sibling traversal.
- **Event Dispatch Algorithm (`src/dom/events.zig`):** Standard 3-phase event propagation:
  1. Capture phase (root down to target parent).
  2. At-target phase.
  3. Bubbling phase (target parent up to root).
- **Mutation Observers (`src/dom/mutation.zig`):** Asynchronous DOM change delivery batching childList, attribute, and characterData records.
- **Web Components (`src/dom/components.zig`):** Shadow DOM tree encapsulation, open/closed modes, and Custom Element registry.

---

## 4. CSS Engine & Style Cascade (`src/css/`)

- **Lexer & Parser:** Parses CSS stylesheets, rule blocks, selectors, and property declarations.
- **Selector Matching & Specificity (`selector.zig`):**
  - Specificity calculated as a standard 3-tuple `(a, b, c)`: ID selectors, Class/Attribute/Pseudo selectors, and Tag/Element selectors.
  - Matches tag names, `.class` attributes, `#id` attributes, and descendant combinators.
- **Computed Style Cascade (`style.zig`):**
  - Applies user-agent base stylesheets, author stylesheets, and inline `style="..."` attributes.
  - Resolves CSS inheritance for font size, color, line height, and text alignment.

---

## 5. Layout Engine (`src/layout/`)

- **Layout Tree Constructor (`tree.zig`):** Transforms styled DOM into a tree of `LayoutBox` elements, skipping `display: none` elements.
- **Block Formatting Context (`block.zig`):** Computes margin, border, padding, width, and content height following CSS box model specifications.
- **Flexbox Algorithm (`flex.zig`):** Computes main and cross axis dimensions, flex-grow, flex-shrink, justify-content (`FlexStart`, `FlexEnd`, `Center`, `SpaceBetween`, `SpaceAround`), and align-items (`FlexStart`, `Center`, `FlexEnd`, `Stretch`).
- **CSS Grid Algorithm (`grid.zig`):** Track sizing, auto-placement, column widths, and row offsets.
- **Text Layout & Shaping (`text.zig`):** Word breaking, whitespace collapse, FreeType font metric calculation, and line wrapping.
- **Spatial Hit Testing (`hit_test.zig`):** Resolves mouse click coordinates `(x, y)` to the deepest interactive layout box.

---

## 6. Retained Rendering & Compositing (`src/rendering/`, `src/graphics/`)

- **Display List Generation:** Translates layout tree into retained drawing commands (`DrawRect`, `DrawBorder`, `DrawText`, `PushClip`, `PopClip`).
- **Scene Graph & Stacking Contexts (`scene_graph.zig`):** Z-index stacking context sorting guaranteeing correct rendering order.
- **Tile Cache & Damage Tracking (`tile_cache.zig`):** Divides viewport into 256x256 tiles, invalidating only dirty tiles when DOM or layout changes occur.
- **CPU Software Rasterizer (`graphics/software.zig`):** Highly optimized 32-bit ARGB software rasterizer with Porter-Duff alpha blending and direct PPM P6 image capture.
- **Vulkan Graphics Backend (`graphics/vulkan.zig`):** Hardware GPU backend integrating instance creation, physical device selection, pipeline creation, and swapchain presentation.

---

## 7. Networking Subsystem (`src/net/`)

- **DNS Resolver (`dns.zig`):** Resolves domain names to IPv4 addresses using libc `getaddrinfo` with thread-safe caching and TTL expiration.
- **TLS 1.3 Client (`tls.zig`):** OpenSSL integration with ALPN negotiation (`h2`, `http/1.1`), Server Name Indication (SNI), and root CA certificate validation.
- **HTTP/1.1 Client (`http1.zig`):** Socket connection, keep-alive connection reuse, chunked transfer decoding, and response parsing.
- **HTTP/2 Engine (`http2.zig`):** Frame header parsing (DATA, HEADERS, SETTINGS, PING, GOAWAY) and HPACK static table header decoding.
- **HTTP/3 & QUIC (`http3.zig`):** QUIC packet header parsing (Long/Short headers) and HTTP/3 frame decoding.
- **Cookie Jar (`cookies.zig`):** RFC 6265 compliant cookie management with domain matching, path matching, SameSite (Strict, Lax, None), Secure, and HttpOnly enforcement.
- **HTTP Cache (`cache.zig`):** RFC 7234 memory cache respecting `Cache-Control`, `max-age`, and `ETag`.

---

## 8. Memory Efficiency & OS Accounting (`src/common/memory.zig`)

Memory efficiency is a core architectural requirement of Davoth:

1. **Subsystem Accounting:**
   - 14 distinct subsystems independently account for memory allocations: `DOM`, `Layout`, `JSHeap`, `WASMHeap`, `CSS`, `Style`, `RenderDisplayList`, `NetworkCache`, `ImageDecoders`, `Storage`, `ExtensionRuntime`, `Compositor`, `GPU`, `General`.
   - Each subsystem tracks active bytes, peak allocation, and total allocation count.
2. **Kernel Metrics Reading:**
   - Directly parses Linux `/proc/self/status` and `/proc/self/smaps_rollup` to report actual Resident Set Size (RSS), Proportional Set Size (PSS), and Unique Set Size (USS).
3. **Slab Allocator:**
   - Custom slab allocator (`SlabAllocator`) allocating fixed 64-byte slots in 64KB pages to eliminate memory fragmentation.
4. **Bounded Caches & OS Page Release:**
   - LRU eviction policies bound cache size.
   - Released memory pages are returned to the Linux kernel via `posix.madvise(..., MADV_DONTNEED)`.
