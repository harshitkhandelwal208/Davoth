//! Davoth Browser Root Module - Comprehensive re-exports and integration tests.
const std = @import("std");

// Subsystems
pub const common = struct {
    pub const types = @import("common/types.zig");
    pub const memory = @import("common/memory.zig");
    pub const string = @import("common/string.zig");
    pub const url = @import("common/url.zig");
    pub const ipc = @import("common/ipc.zig");
    pub const c = @import("common/c.zig");
    pub const sync = @import("common/sync.zig");
    pub const time = @import("common/time.zig");
    pub const fs = @import("common/fs.zig");
};

pub const js = struct {
    pub const value = @import("js/value.zig");
    pub const object = @import("js/object.zig");
    pub const gc = @import("js/gc.zig");
    pub const lexer = @import("js/lexer.zig");
    pub const ast = @import("js/ast.zig");
    pub const parser = @import("js/parser.zig");
    pub const bytecode = @import("js/bytecode.zig");
    pub const interpreter = @import("js/interpreter.zig");
    pub const jit = @import("js/jit.zig");
    pub const builtins = @import("js/builtins.zig");
    pub const promise = @import("js/promise.zig");
    pub const modules = @import("js/modules.zig");
};

pub const wasm = struct {
    pub const types = @import("wasm/types.zig");
    pub const decoder = @import("wasm/decoder.zig");
    pub const validator = @import("wasm/validator.zig");
    pub const runtime = @import("wasm/runtime.zig");
};

pub const html = struct {
    pub const tokenizer = @import("html/tokenizer.zig");
    pub const tree_builder = @import("html/tree_builder.zig");
};

pub const dom = struct {
    pub const node = @import("dom/node.zig");
    pub const events = @import("dom/events.zig");
    pub const mutation = @import("dom/mutation.zig");
    pub const components = @import("dom/components.zig");
};

pub const css = struct {
    pub const lexer = @import("css/lexer.zig");
    pub const selector = @import("css/selector.zig");
    pub const properties = @import("css/properties.zig");
    pub const parser = @import("css/parser.zig");
    pub const style = @import("css/style.zig");
};

pub const layout = struct {
    pub const box = @import("layout/box.zig");
    pub const text = @import("layout/text.zig");
    pub const flex = @import("layout/flex.zig");
    pub const grid = @import("layout/grid.zig");
    pub const block = @import("layout/block.zig");
    pub const tree = @import("layout/tree.zig");
    pub const reflow = @import("layout/reflow.zig");
    pub const hit_test = @import("layout/hit_test.zig");
};

pub const rendering = struct {
    pub const display_list = @import("rendering/display_list.zig");
    pub const tile_cache = @import("rendering/tile_cache.zig");
    pub const scene_graph = @import("rendering/scene_graph.zig");
    pub const compositor = @import("rendering/compositor.zig");
};

pub const graphics = struct {
    pub const backend = @import("graphics/backend.zig");
    pub const software = @import("graphics/software.zig");
    pub const vulkan = @import("graphics/vulkan.zig");
};

pub const net = struct {
    pub const dns = @import("net/dns.zig");
    pub const tls = @import("net/tls.zig");
    pub const http1 = @import("net/http1.zig");
    pub const http2 = @import("net/http2.zig");
    pub const http3 = @import("net/http3.zig");
    pub const cookies = @import("net/cookies.zig");
    pub const cache = @import("net/cache.zig");
    pub const websocket = @import("net/websocket.zig");
    pub const download = @import("net/download.zig");
};

pub const webapis = struct {
    pub const fetch = @import("webapis/fetch.zig");
    pub const xhr = @import("webapis/xhr.zig");
    pub const storage = @import("webapis/storage.zig");
    pub const canvas = @import("webapis/canvas.zig");
    pub const indexeddb = @import("webapis/indexeddb.zig");
    pub const worker = @import("webapis/worker.zig");
    pub const media = @import("webapis/media.zig");
};

pub const media = struct {
    pub const image = @import("media/image.zig");
    pub const font = @import("media/font.zig");
    pub const audio = @import("media/audio.zig");
};

pub const storage = struct {
    pub const db = @import("storage/db.zig");
    pub const history = @import("storage/history.zig");
    pub const bookmarks = @import("storage/bookmarks.zig");
    pub const sessions = @import("storage/sessions.zig");
    pub const preferences = @import("storage/preferences.zig");
};

pub const security = struct {
    pub const origin = @import("security/origin.zig");
    pub const cors = @import("security/cors.zig");
    pub const csp = @import("security/csp.zig");
    pub const sandbox = @import("security/sandbox.zig");
    pub const permissions = @import("security/permissions.zig");
    pub const certs = @import("security/certs.zig");
};

pub const accessibility = struct {
    pub const tree = @import("accessibility/tree.zig");
    pub const navigation = @import("accessibility/navigation.zig");
    pub const atspi = @import("accessibility/atspi.zig");
};

pub const devtools = struct {
    pub const inspector = @import("devtools/inspector.zig");
    pub const debugger = @import("devtools/debugger.zig");
    pub const network = @import("devtools/network.zig");
    pub const profiler = @import("devtools/profiler.zig");
};

pub const ui = struct {
    pub const tabs = @import("ui/tabs.zig");
    pub const urlbar = @import("ui/urlbar.zig");
    pub const reader_mode = @import("ui/reader_mode.zig");
    pub const pdf_viewer = @import("ui/pdf_viewer.zig");
    pub const pip = @import("ui/pip.zig");
    pub const capture = @import("ui/capture.zig");
    pub const theme = @import("ui/theme.zig");
    pub const vim = @import("ui/vim.zig");
    pub const sync = @import("ui/sync.zig");
    pub const shell = @import("ui/shell.zig");
    pub const gtk_app = @import("ui/gtk_app.zig");
};

pub const extensions = struct {
    pub const manifest = @import("extensions/manifest.zig");
    pub const xpi = @import("extensions/xpi.zig");
    pub const runtime = @import("extensions/runtime.zig");
    pub const filter_list = @import("extensions/filter_list.zig");
    pub const apis = struct {
        pub const tabs_api = @import("extensions/apis/tabs_api.zig");
        pub const storage_api = @import("extensions/apis/storage_api.zig");
        pub const runtime_api = @import("extensions/apis/runtime_api.zig");
        pub const web_request_api = @import("extensions/apis/web_request_api.zig");
        pub const dnr_api = @import("extensions/apis/dnr_api.zig");
    };
    pub const tabs_api = apis.tabs_api;
    pub const storage_api = apis.storage_api;
    pub const runtime_api = apis.runtime_api;
    pub const web_request_api = apis.web_request_api;
    pub const dnr_api = apis.dnr_api;
};

pub const bitwarden = struct {
    pub const crypto = @import("components/bitwarden/crypto.zig");
    pub const vault = @import("components/bitwarden/vault.zig");
    pub const autofill = @import("components/bitwarden/autofill.zig");
    pub const sync = @import("components/bitwarden/sync.zig");
    pub const ui = @import("components/bitwarden/ui.zig");
};

pub const tools = struct {
    pub const adnauseam_updater = @import("tools/adnauseam_updater/updater.zig");
    pub const bitwarden_updater = @import("tools/bitwarden_updater/updater.zig");
    pub const wpt_runner = @import("tools/wpt_runner.zig");
    pub const test262_runner = @import("tools/test262_runner.zig");
    pub const fuzzer = @import("tools/fuzzer.zig");
};

test "subsystem full verification" {
    std.testing.refAllDecls(@This());
}
