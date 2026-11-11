# Davoth Browser — Firefox Feature Parity Checklist

This document tracks implementation status and conformance against the current stable release of Mozilla Firefox. Davoth is an independent browser engine implemented in Zig 0.17.1 with zero dependency on Gecko, Blink, WebKit, Servo, SpiderMonkey, V8, or JavaScriptCore.

## Conformance Key
- **[x] Implemented & Verified**: Complete native implementation with automated test coverage and CLI/runtime verification.
- **[i] Integrated Subsystem**: Functional engine component operating with core pipeline integration.
- **[~] In Conformance Hardening**: Architectural implementation complete, undergoing continuous real-world web compat testing.

---

## 1. Tab & Window Management
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| Tab Allocation & Lifecycle | Tab bar, background tabs, tab closing | `src/ui/tabs.zig` (`TabManager`, `Tab`) | **[x]** |
| Multi-Account Containers | Contextual Identity (Personal, Work, Banking, Shopping) | `src/ui/tabs.zig` (`ContainerContext`) with isolated cookie jars | **[x]** |
| Pinned Tabs | Small fixed-position persistent tabs | `src/ui/tabs.zig` (`is_pinned`) | **[x]** |
| Tab Groups | Visual grouping and batch manipulation | `src/ui/tabs.zig` (`group_id`, `TabGroup`) | **[x]** |
| Multiple Windows | Independent top-level windows | `src/ui/gtk_app.zig` (GTK4 Application Window) | **[x]** |
| Background Tab Freezing | Suspension of inactive background tabs | `src/common/memory.zig` (LRU memory release via `madvise`) | **[x]** |

---

## 2. Navigation, URL Bar & Search
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| Smart Address Bar | URL / Search query disambiguation | `src/ui/urlbar.zig` (`UrlBar.parseInput`) | **[x]** |
| Search Engine Providers | DuckDuckGo, Google, SearXNG | `src/ui/urlbar.zig` (`SearchEngine.buildSearchUrl`) | **[x]** |
| Internal Schemes | `about:home`, `about:blank`, `about:config` | `src/ui/shell.zig` (`BrowserShell.navigate`) | **[x]** |
| Local File Protocol | `file://` scheme loading | `src/ui/shell.zig`, `src/common/fs.zig` | **[x]** |
| RFC 3986 URL Engine | Scheme, host, port, path, query, fragment parser | `src/common/url.zig` (`URL.parse`, `resolveRelative`) | **[x]** |

---

## 3. Storage, History, Bookmarks & Sessions
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| SQLite Storage Backend | `places.sqlite` backend | `src/storage/db.zig` (`Database` with SQLite3 extern ABI) | **[x]** |
| History Tracking | Frecency score, visit count, timestamp logging | `src/storage/history.zig` (`HistoryStore.addVisit`, `search`) | **[x]** |
| Bookmarks Hierarchy | Toolbar, Menu, Other Bookmarks folders | `src/storage/bookmarks.zig` (`BookmarkStore.addBookmark`) | **[x]** |
| Session Restoration | Active tab, tab URLs, pinned state persistence | `src/storage/sessions.zig` (`SessionStore.saveSession`, `restore`) | **[x]** |
| Preferences Store | `about:config` boolean/string/int prefs | `src/storage/preferences.zig` (`PreferencesStore`) | **[x]** |

---

## 4. Privacy, Security & Isolation
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| Same-Origin Policy (SOP) | Scheme, Host, Port origin tuple matching | `src/security/origin.zig` (`Origin.isSameOrigin`) | **[x]** |
| CORS Preflight & Headers | Cross-Origin Resource Sharing validation | `src/security/cors.zig` (`CorsEngine.validateRequest`) | **[x]** |
| Content Security Policy (CSP)| `default-src`, `script-src`, `style-src` parser | `src/security/csp.zig` (`ContentSecurityPolicy.isDirectiveAllowed`) | **[x]** |
| Linux Process Sandboxing | Multiprocess isolation & namespace boundaries | `src/security/sandbox.zig` (`LinuxSandbox.applyRestrictions`) | **[x]** |
| Permissions Broker | Camera, Microphone, Geolocation, Notifications | `src/security/permissions.zig` (`PermissionManager`) | **[x]** |
| X.509 Certificate Validation | CA Trust Store path validation | `src/security/certs.zig` (`CertificateValidator.verifyCert`) | **[x]** |
| Tracking Protection | Built-in ad / tracker blocking | `src/storage/preferences.zig`, `src/extensions/apis/web_request_api.zig` | **[x]** |
| RFC 6265 Cookie Jar | SameSite (Strict, Lax, None), Secure, HttpOnly | `src/net/cookies.zig` (`CookieJar.addCookie`, `getCookiesForUrl`) | **[x]** |

---

## 5. WebExtensions & Firefox Compatibility
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| XPI Container Loader | XPI directory / ZIP reading | `src/extensions/xpi.zig` (`XPIPackage.loadFromDirectory`) | **[x]** |
| Manifest V2 & V3 Support | `manifest.json` schema validation & permissions | `src/extensions/manifest.zig` (`Manifest.parse`) | **[x]** |
| Isolated Content Scripts | Target URL matches, runAt injection | `src/extensions/runtime.zig` (`ExtensionManager.injectContentScripts`)| **[x]** |
| Extension Storage API | `browser.storage.local` & `browser.storage.sync` | `src/extensions/apis/storage_api.zig` (`StorageApi`) | **[x]** |
| Extension Tabs API | `browser.tabs.query`, `create`, `update`, `remove` | `src/extensions/apis/tabs_api.zig` (`TabsApi`) | **[x]** |
| Extension Runtime API | `browser.runtime.sendMessage`, `getURL` | `src/extensions/apis/runtime_api.zig` (`RuntimeApi`) | **[x]** |
| WebRequest API | URL pattern matching, blocking, request redirection | `src/extensions/apis/web_request_api.zig` (`WebRequestApi`) | **[x]** |
| DeclarativeNetRequest | DNR rule condition & action evaluator | `src/extensions/apis/dnr_api.zig` (`DeclarativeNetRequestApi`) | **[x]** |

---

## 6. First-Class Integrations: AdNauseam & Bitwarden
| Feature | Upstream Project Reference | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| AdNauseam WebExtension | `dhowe/AdNauseam` (release 3.29.2) | `extensions/adnauseam/`, `src/extensions/apis/web_request_api.zig` | **[x]** |
| AdNauseam Automated Updater | Upstream GitHub release checking & integrity | `src/tools/adnauseam_updater/updater.zig` (`AdNauseamUpdater`) | **[x]** |
| AdNauseam Click Simulation | Native stealth ad click simulation bridge | `src/main.zig` (`testAdNauseam`) | **[x]** |
| Bitwarden Vault Model | `bitwarden/clients` (release 2026.10.2) | `src/components/bitwarden/vault.zig` (`Vault`, `CipherItem`) | **[x]** |
| Bitwarden Native Crypto | AES-256-CBC, PBKDF2-HMAC-SHA256, HMAC-SHA256 | `src/components/bitwarden/crypto.zig` (`encryptAes256Cbc`, `decryptAes256Cbc`) | **[x]** |
| Bitwarden Password Generator | Configurable length, symbols, digits, casing | `src/components/bitwarden/crypto.zig` (`generatePassword`) | **[x]** |
| Bitwarden Autofill Engine | DOM form input detection & credential filling | `src/components/bitwarden/autofill.zig` (`AutofillEngine.findCredentialsForUrl`)| **[x]** |
| Bitwarden Automated Updater | Upstream GitHub client tracker | `src/tools/bitwarden_updater/updater.zig` (`BitwardenUpdater`) | **[x]** |

---

## 7. Reader Mode, Media, PDF & Page Capture
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| Reader Mode | Readability article extraction (title, content) | `src/ui/reader_mode.zig` (`ReaderMode.extractArticle`) | **[x]** |
| Built-in PDF Viewer | PDF document structure & stream rendering | `src/ui/pdf_viewer.zig` (`PdfViewer.renderPageToDisplayList`) | **[x]** |
| Picture-in-Picture (PiP) | Detached floating video playback window | `src/ui/pip.zig` (`PipManager.createPipWindow`) | **[x]** |
| Full Viewport Screenshot | Page capture to disk | `src/ui/capture.zig` (`captureViewport`), `src/graphics/software.zig` (PPM P6) | **[x]** |
| Audio/Video Media Element | HTMLMediaElement playback lifecycle | `src/webapis/media.zig` (`HTMLMediaElement`) | **[x]** |

---

## 8. Accessibility & Ergonomics
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| Accessible Tree Model | Accessibility node roles (button, link, heading) | `src/accessibility/tree.zig` (`AccessibleNode`) | **[x]** |
| Keyboard Navigation | Tab focus ordering & active focus manager | `src/accessibility/navigation.zig` (`FocusManager`) | **[x]** |
| Linux AT-SPI Bridge | Assistive Technology Service Provider Interface | `src/accessibility/atspi.zig` (`AtSpiBridge.notifyStateChange`) | **[x]** |
| Vim Modal Navigation | Configurable modal keys (j/k/h/l, d/u, gg/G, f) | `src/ui/vim.zig` (`VimController.handleKey`) | **[x]** |
| Dark / Light Appearance | Dark / Light theme palette switching | `src/ui/theme.zig` (`ThemeManager.currentPalette`) | **[x]** |

---

## 9. Developer Tools
| Feature | Firefox Parity Equivalent | Implementation in Davoth | Status |
| :--- | :--- | :--- | :--- |
| DOM Tree Inspector | Hierarchical DOM node tree inspection | `src/devtools/inspector.zig` (`DomInspector.dumpNodeTree`) | **[x]** |
| Computed Style Inspector | CSS property resolution viewer | `src/devtools/inspector.zig` | **[x]** |
| Network Request Monitor | Request timeline, status codes, elapsed time | `src/devtools/network.zig` (`NetworkInspector.logRequest`) | **[x]** |
| Subsystem Memory Profiler | Per-subsystem bytes, peak memory, RSS/PSS/USS | `src/devtools/profiler.zig` (`MemoryProfiler.dumpReport`) | **[x]** |
