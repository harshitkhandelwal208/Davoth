# Davoth Browser — WebExtensions Compatibility Architecture

Davoth implements native compatibility with the **Firefox WebExtensions** API, allowing real, unmodified Firefox browser extensions to run directly.

---

## 1. Extension Lifecycle & Architecture

```
+-------------------------------------------------------------------------------+
|                             EXTENSION LIFECYCLE                               |
+-------------------------------------------------------------------------------+
|  1. XPI Package / Directory Extraction (`src/extensions/xpi.zig`)              |
|  2. Manifest Parsing & Schema Validation (`src/extensions/manifest.zig`)       |
|  3. Permission Brokering & User Consent Gating                                |
|  4. Background Context Initialization (Event Pages / Service Workers)          |
|  5. Isolated Content Script Injection (`src/extensions/runtime.zig`)           |
|  6. Bi-directional Message Passing (`src/extensions/apis/runtime_api.zig`)   |
+-------------------------------------------------------------------------------+
```

---

## 2. Manifest V2 & Manifest V3 Support

Davoth supports both Manifest V2 (used by extensions like AdNauseam and classic uBlock Origin) and Manifest V3:

| Field | Manifest V2 Support | Manifest V3 Support |
| :--- | :--- | :--- |
| `manifest_version` | Supported (`2`) | Supported (`3`) |
| `name`, `version`, `description` | Parsed & validated | Parsed & validated |
| `permissions` | API & host permissions | API permissions |
| `host_permissions` | Merged into `permissions` | Explicit host permissions array |
| `background` | `scripts` array + `persistent` flag | `service_worker` or `scripts` |
| `content_scripts` | `matches`, `js`, `css`, `run_at` | `matches`, `js`, `css`, `run_at` |
| `browser_action` | Icon, popup, title | Re-mapped to `action` |
| `action` | Re-mapped to `browser_action` | Native action button & popup |
| `web_accessible_resources` | Array of glob strings | Structured objects with `matches` |

---

## 3. Isolated Content Script Execution

Content scripts run with full access to the page DOM but in an **isolated world**:
- **DOM Access:** Content scripts query and manipulate DOM nodes directly without crossing process boundaries.
- **Variable Isolation:** JavaScript variables and objects defined by content scripts cannot be accessed or overridden by page scripts. Page script prototypes cannot tamper with extension prototypes.
- **Timing (`run_at`):**
  - `document_start`: Executed before any DOM construction begins.
  - `document_end`: Executed immediately after DOMContentLoaded.
  - `document_idle`: Executed when main thread is idle after page load.

---

## 4. Supported Extension APIs

### `browser.webRequest` (`src/extensions/apis/web_request_api.zig`)
- Intercepts outgoing HTTP/HTTPS network requests.
- URL pattern matching supporting wildcards (`*://*.doubleclick.net/*`).
- Actions:
  - `cancel: true` (block tracking and advertisement requests).
  - `redirectUrl` (redirect requests to local placeholders or mirrors).
- Synchronous `blocking` mode for instant ad filtering.

### `browser.declarativeNetRequest` (`src/extensions/apis/dnr_api.zig`)
- Declarative rule engine evaluating URL filters and domain conditions.
- Rule actions: `block`, `allow`, `redirect`, `modifyHeaders`.
- High-performance pattern matcher bypassing JavaScript callbacks.

### `browser.tabs` (`src/extensions/apis/tabs_api.zig`)
- `query()`: Filter tabs by active state, window, or URL pattern.
- `create()`: Open new tabs in specified windows or containers.
- `update()`: Navigate tabs or change active tab selection.
- `remove()`: Close tabs cleanly.

### `browser.storage` (`src/extensions/apis/storage_api.zig`)
- `storage.local`: Persistent local key-value storage backed by SQLite.
- `storage.sync`: Synced key-value storage encrypted across user devices.
- Quota management and change event broadcasting (`onChanged`).

### `browser.runtime` (`src/extensions/apis/runtime_api.zig`)
- `sendMessage()`: Message passing between content scripts and background scripts.
- `onMessage`: Event listener for incoming structured messages.
- `getURL()`: Resolves relative paths to internal `davoth-extension://<id>/...` URLs.

---

## 5. Popular Extension Target Compatibility

| Extension | Upstream Repository | Compatibility Status in Davoth |
| :--- | :--- | :--- |
| **AdNauseam** | `https://github.com/dhowe/AdNauseam` | **Native First-Class Supported** (verified manifest & blocking) |
| **Bitwarden** | `https://github.com/bitwarden/clients`| **Native First-Class Integrated** (native vault, autofill, crypto) |
| **uBlock Origin** | `https://github.com/gorhill/uBlock` | Compatible (WebRequest, Storage, Content Scripts) |
| **Dark Reader** | `https://github.com/darkreader/darkreader` | Compatible (CSS injection, DOM mutation observers) |
| **Violentmonkey** | `https://github.com/violentmonkey/violentmonkey` | Compatible (Userscript execution, runtime messaging) |
