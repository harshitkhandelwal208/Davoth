//! Browser Shell orchestrating tabs, navigation, DOM, JavaScript VM, rendering, and extensions.
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
const GarbageCollector = @import("../js/gc.zig").GarbageCollector;
const VM = @import("../js/interpreter.zig").VM;
const JSValue = @import("../js/value.zig").JSValue;
const Parser = @import("../js/parser.zig").Parser;
const BytecodeCompiler = @import("../js/bytecode.zig").BytecodeCompiler;
const JITCompiler = @import("../js/jit.zig").JITCompiler;

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
    gc: *GarbageCollector,
    vm: *VM,
    jit: ?*JITCompiler,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*BrowserShell {
        const shell = try allocator.create(BrowserShell);
        const table = try AtomTable.init(allocator);
        const style_eng = try StyleEngine.init(allocator, table);
        const hist = try HistoryStore.initInMemory(allocator);

        const gc = try GarbageCollector.init(allocator);
        const vm = try VM.init(allocator, table, gc);
        const jit = try allocator.create(JITCompiler);
        jit.* = JITCompiler.init(allocator);
        vm.jit = jit;

        shell.* = .{
            .allocator = allocator,
            .atom_table = table,
            .tab_manager = TabManager.init(allocator),
            .style_engine = style_eng,
            .extension_manager = ExtensionManager.init(allocator),
            .vault = Vault.init(allocator),
            .history_store = hist,
            .http_client = HttpClient.init(allocator),
            .rasterizer = try SoftwareRasterizer.init(allocator, width, height),
            .compositor = undefined,
            .gc = gc,
            .vm = vm,
            .jit = jit,
        };
        shell.compositor = Compositor.init(shell.rasterizer.backend());

        // Open initial home tab
        _ = try shell.tab_manager.newTab("about:home", "Davoth Home", .Default);
        return shell;
    }

    pub fn deinit(self: *BrowserShell) void {
        if (self.jit) |j| {
            j.deinit();
            self.allocator.destroy(j);
        }
        self.vm.deinit();
        self.gc.deinit();
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

    pub fn evalScript(self: *BrowserShell, js_src: []const u8) !JSValue {
        var parser = Parser.init(self.allocator, js_src);
        const ast = try parser.parseProgram();
        defer ast.deinit(self.allocator);

        var compiler = BytecodeCompiler.init(self.allocator, self.atom_table, "script");
        var code = try compiler.compile(ast);
        defer code.deinit();

        return try self.vm.execute(&code);
    }

    fn executeInlineScripts(self: *BrowserShell, node: *Node) void {
        if (node.node_type == .Element) {
            const script_atom = self.atom_table.intern("script") catch return;
            if (node.tag_name == script_atom) {
                var code_text: ?[]const u8 = null;
                if (node.text_content) |t| {
                    code_text = t;
                } else if (node.first_child) |fc| {
                    if (fc.node_type == .Text and fc.text_content != null) {
                        code_text = fc.text_content;
                    }
                }

                if (code_text) |src| {
                    if (src.len > 0) {
                        _ = self.evalScript(src) catch |err| {
                            std.debug.print("Embedded script execution error: {any}\n", .{err});
                        };
                    }
                }
            }
        }

        var curr = node.first_child;
        while (curr) |child| {
            self.executeInlineScripts(child);
            curr = child.next_sibling;
        }
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
                \\    <script>let status = "Davoth Engine Active";</script>
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

        // Execute inline script tags
        self.executeInlineScripts(doc);

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

        // Update active tab URL
        if (self.tab_manager.activeTab()) |tab| {
            self.allocator.free(tab.url);
            tab.url = try self.allocator.dupe(u8, effective_url);
        }

        // Record history
        try self.history_store.addVisit(effective_url, "Web Page");
    }
};

test "browser shell initialization, navigation, and script execution" {
    const allocator = std.testing.allocator;
    const shell = try BrowserShell.init(allocator, 800, 600);
    defer shell.deinit();

    try shell.navigate("about:home");
    try std.testing.expectEqual(@as(usize, 1), shell.tab_manager.tabs.items.len);

    const val = try shell.evalScript("let x = 10; let y = 20; return x + y;");
    try std.testing.expectEqual(@as(f64, 30.0), val.toFloat64());
}
