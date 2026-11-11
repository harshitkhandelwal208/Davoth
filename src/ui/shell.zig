//! Browser Shell orchestrating tabs, navigation, rendering, and extensions.
const std = @import("std");
const TabManager = @import("tabs.zig").TabManager;
const UrlBar = @import("urlbar.zig").UrlBar;
const SearchEngine = @import("urlbar.zig").SearchEngine;
const AtomTable = @import("../common/string.zig").AtomTable;
const Node = @import("../dom/node.zig").Node;
const TreeBuilder = @import("../html/tree_builder.zig").TreeBuilder;
const StyleEngine = @import("../css/style.zig").StyleEngine;
const LayoutBox = @import("../layout/box.zig").LayoutBox;
const buildLayoutTree = @import("../layout/tree.zig").buildLayoutTree;
const performLayout = @import("../layout/reflow.zig").performLayout;
const DisplayList = @import("../rendering/display_list.zig").DisplayList;
const SoftwareRasterizer = @import("../graphics/software.zig").SoftwareRasterizer;
const Compositor = @import("../rendering/compositor.zig").Compositor;
const ExtensionManager = @import("../extensions/runtime.zig").ExtensionManager;
const Vault = @import("../components/bitwarden/vault.zig").Vault;
const HistoryStore = @import("../storage/history.zig").HistoryStore;
const HttpClient = @import("../net/http1.zig").HttpClient;
const fs = @import("../common/fs.zig");

pub const BrowserShell = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    tab_manager: TabManager,
    style_engine: *StyleEngine,
    extension_manager: ExtensionManager,
    vault: Vault,
    history_store: HistoryStore,
    http_client: HttpClient,
    rasterizer: SoftwareRasterizer,
    compositor: Compositor,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*BrowserShell {
        const shell = try allocator.create(BrowserShell);
        const table = try AtomTable.init(allocator);
        const style_eng = try StyleEngine.init(allocator, table);
        const hist = try HistoryStore.initInMemory(allocator);
        var raster = try SoftwareRasterizer.init(allocator, width, height);
        const comp = Compositor.init(raster.backend());

        shell.* = .{
            .allocator = allocator,
            .atom_table = table,
            .tab_manager = TabManager.init(allocator),
            .style_engine = style_eng,
            .extension_manager = ExtensionManager.init(allocator),
            .vault = Vault.init(allocator),
            .history_store = hist,
            .http_client = HttpClient.init(allocator),
            .rasterizer = raster,
            .compositor = comp,
        };

        // Open initial home tab
        _ = try shell.tab_manager.newTab("about:home", "Davoth Home", .Default);
        return shell;
    }

    pub fn deinit(self: *BrowserShell) void {
        self.tab_manager.deinit();
        self.style_engine.deinit();
        self.extension_manager.deinit();
        self.vault.deinit();
        self.history_store.deinit();
        self.http_client.deinit();
        self.rasterizer.deinit();
        self.atom_table.deinit();
        self.allocator.destroy(self);
    }

    pub fn navigate(self: *BrowserShell, input_url: []const u8) !void {
        const url = try UrlBar.parseInput(self.allocator, input_url, .DuckDuckGo);
        defer self.allocator.free(url);

        // Check WebRequest blocking
        const intercept = self.extension_manager.web_request.interceptRequest(url);
        if (intercept.cancel) {
            std.debug.print("Navigation blocked by WebRequest extension policy: {s}\n", .{url});
            return;
        }

        const effective_url = intercept.redirect_url orelse url;

        // Fetch or generate HTML
        var html: []const u8 = "";
        var need_free_html = false;

        if (std.mem.startsWith(u8, effective_url, "about:home") or std.mem.startsWith(u8, effective_url, "about:blank")) {
            html =
                \\<!DOCTYPE html>
                \\<html>
                \\  <head><title>Davoth - Independent Browser</title></head>
                \\  <body>
                \\    <div style="background-color: #1e1e2e; color: #ffffff; padding: 40px; margin: 20px;">
                \\      <h1>Davoth Browser</h1>
                \\      <p>Independent, secure, memory-efficient browser built from scratch in Zig 0.17.1</p>
                \\    </div>
                \\  </body>
                \\</html>
            ;
        } else if (std.mem.startsWith(u8, effective_url, "file://")) {
            const path = effective_url[7..];
            html = try fs.readFileAlloc(self.allocator, path, 10 * 1024 * 1024);
            need_free_html = true;
        } else {
            const resp = try self.http_client.get(effective_url);
            html = resp.body;
            need_free_html = true;
        }
        defer if (need_free_html) self.allocator.free(html);

        // Parse HTML into DOM
        var builder = try TreeBuilder.init(self.allocator, self.atom_table, html);
        defer builder.deinit();

        const doc = try builder.parse();
        defer doc.deinit(self.allocator);

        // Inject content scripts
        self.extension_manager.injectContentScripts(effective_url, doc);

        // Build layout tree
        const layout_root_opt = try buildLayoutTree(self.allocator, doc, self.style_engine, null);
        if (layout_root_opt) |layout_root| {
            defer layout_root.deinit(self.allocator);

            // Reflow
            performLayout(layout_root, @floatFromInt(self.rasterizer.width), @floatFromInt(self.rasterizer.height));

            // Generate Display List
            var dlist = DisplayList.init(self.allocator);
            defer dlist.deinit();

            try dlist.build(layout_root);

            // Composite
            self.compositor.composite(&dlist, null);
        }

        // Record history
        try self.history_store.addVisit(effective_url, "Web Page");
    }
};

test "browser shell initialization and navigation" {
    const allocator = std.testing.allocator;
    const shell = try BrowserShell.init(allocator, 800, 600);
    defer shell.deinit();

    try shell.navigate("about:home");
    try std.testing.expectEqual(@as(usize, 1), shell.tab_manager.tabs.items.len);
}
