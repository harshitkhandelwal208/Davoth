# Davoth Browser — AdNauseam Integration Architecture

Davoth provides **first-class, native support** for **AdNauseam**, the anti-tracking and obfuscation browser extension that blocks advertisements and simulates automatic stealth ad clicks to poison surveillance advertising profiles.

- **Upstream Repository:** `https://github.com/dhowe/AdNauseam`
- **Integrated Upstream Release:** `adnauseam-3.29.2.firefox.zip`
- **License:** GNU General Public License v3.0 (preserved in `extensions/adnauseam/LICENSE`)

---

## 1. Architectural Philosophy

AdNauseam is **not** an imitation or superficial mock inside Davoth. It operates as a genuine WebExtension utilizing Davoth's WebExtensions runtime, `browser.webRequest`, `browser.storage`, and content script injection engines.

```
+-------------------------------------------------------------------------------+
|                       ADNAUSEAM SUBSYSTEM ARCHITECTURE                        |
+-------------------------------------------------------------------------------+
|                                                                               |
|   [ Upstream Package: extensions/adnauseam/upstream/adnauseam-firefox.zip ]   |
|                                     |                                         |
|                                     v                                         |
|                 [ WebExtensions Runtime Loader (xpi.zig) ]                     |
|                                     |                                         |
|               +---------------------+---------------------+                   |
|               |                                           |                   |
|               v                                           v                   |
|   [ WebRequest Blocking Engine ]             [ Stealth Click Simulator ]      |
|   - Blocks telemetry & tracking              - Parses outgoing ad links       |
|   - Filters doubleclick, google-analytics    - Dispatches stealth visits      |
|   - Preserves user privacy                   - Obfuscates browsing profile    |
|                                                                               |
|                                     |                                         |
|                                     v                                         |
|             [ Automated Upstream Updater (updater.zig) ]                      |
|             - Checks GitHub API for upstream releases                         |
|             - Computes SHA-256 checksum verification                          |
|             - Performs automated regression test validation                   |
+-------------------------------------------------------------------------------+
```

---

## 2. WebRequest Filtering Engine Integration

AdNauseam specifies strict filtering rules that Davoth evaluates synchronously:

```zig
// From src/extensions/apis/web_request_api.zig
var api = WebRequestApi.init(allocator);
try api.addRule(FilterRule{
    .url_pattern = "*://*.doubleclick.net/*",
    .action = .Block,
});
try api.addRule(FilterRule{
    .url_pattern = "*://*.google-analytics.com/*",
    .action = .Block,
});
```

Network requests matching tracking patterns are dropped before DNS resolution or socket creation, saving bandwidth and preventing tracking cookies from being transmitted.

---

## 3. Stealth Click Simulation Bridge

AdNauseam's unique capability is quietly clicking blocked advertisements to introduce noise into tracking profiles:

1. Blocked advertisement URLs are logged to an internal click vault.
2. In the background, synthetic HTTP `GET` requests are dispatched with randomized user agents and isolated cookie containers.
3. Trackers register valid clicks while the user remains completely undisturbed and unmonitored.

---

## 4. Automated Upstream Update Infrastructure (`src/tools/adnauseam_updater/updater.zig`)

To prevent the browser from depending on outdated forks, Davoth includes an automated upstream update detection tool:

```bash
# Automated check for upstream AdNauseam releases
davoth --test-adnauseam
```

The updater tool performs:
1. **GitHub API Polling:** Checks `https://api.github.com/repos/dhowe/AdNauseam/releases/latest` for new tags.
2. **Checksum Integrity:** Downloads the official release archive and verifies the SHA-256 hash.
3. **Automated Regression Suite:** Runs extension tests before staging updates into `extensions/adnauseam/`.
4. **Safety Guarantee:** Never automatically applies unverified code; all changes must pass the Davoth test suite.

---

## 5. Automated Verification

Execute the built-in AdNauseam test suite with:

```bash
./zig-out/bin/davoth --test-adnauseam
```

Output:
```
Running AdNauseam WebExtensions compatibility verification...
AdNauseam Manifest V2 Verification: OK (id: adnauseam@rednoise.org)
AdNauseam WebRequest Blocking Engine: OK
AdNauseam Click Simulation Bridge: OK
```
