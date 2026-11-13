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
const VimController = @import("vim.zig").VimController;
const VimAction = @import("vim.zig").VimAction;
const detectLoginForm = @import("../components/bitwarden/autofill.zig").detectLoginForm;
const autofillForm = @import("../components/bitwarden/autofill.zig").autofillForm;

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
    vim_controller: VimController,
    current_doc: ?*Node = null,
    current_layout: ?*LayoutBox = null,

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
            .vim_controller = VimController.init(allocator),
            .current_doc = null,
            .current_layout = null,
        };
        shell.compositor = Compositor.init(shell.rasterizer.backend());

        // Open initial home tab
        _ = try shell.tab_manager.newTab("about:home", "Davoth Home", .Default);
        return shell;
    }

    pub fn deinit(self: *BrowserShell) void {
        if (self.current_layout) |l| l.deinit(self.allocator);
        if (self.current_doc) |d| d.deinit(self.allocator);
        self.vim_controller.deinit();
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

        // Check WebRequest blocking with AdNauseam recording
        const intercept = self.extension_manager.interceptUrl(url, "main_frame");
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
                \\      <a href="https://davoth.org/docs">Documentation</a>
                \\      <form action="/login"><input type="email" placeholder="Email"><input type="password" placeholder="Password"><button type="submit">Sign In</button></form>
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

        // Check Bitwarden Autofill if vault is unlocked
        if (self.vault.is_unlocked) {
            var logins = self.vault.findLoginsForHost(self.allocator, effective_url) catch null;
            if (logins) |*list| {
                defer list.deinit(self.allocator);
                if (list.items.len > 0 and list.items[0].login != null) {
                    const form = detectLoginForm(doc, self.atom_table);
                    _ = autofillForm(self.allocator, form, list.items[0].login.?, self.atom_table) catch {};
                }
            }
        }

        // Execute inline script tags
        self.executeInlineScripts(doc);

        // Inject content scripts
        self.extension_manager.injectContentScripts(effective_url, doc);

        // Apply AdNauseam cosmetic filtering (element hiding)
        _ = self.extension_manager.applyCosmeticFilters(effective_url, doc, self.atom_table) catch {};

        // Build layout tree
        const layout_root_opt = try buildLayoutTree(self.allocator, doc, self.style_engine, null);
        if (layout_root_opt) |layout_root| {
            // Reflow
            performLayout(layout_root, @floatFromInt(self.rasterizer.width), @floatFromInt(self.rasterizer.height));

            // Generate Display List
            var dlist = DisplayList.init(self.allocator);
            defer dlist.deinit();

            try dlist.build(layout_root);

            // Composite
            self.compositor.composite(&dlist, null);

            // Configure Vim navigation scroll bounds and link hints
            self.vim_controller.setScrollBounds(@floatFromInt(self.rasterizer.height), @floatFromInt(self.rasterizer.width), @floatFromInt(self.rasterizer.height));
            self.vim_controller.generateHints(doc, layout_root, self.atom_table) catch {};

            if (self.current_layout) |l| l.deinit(self.allocator);
            self.current_layout = layout_root;
        } else {
            if (self.current_layout) |l| {
                l.deinit(self.allocator);
                self.current_layout = null;
            }
        }

        if (self.current_doc) |d| d.deinit(self.allocator);
        self.current_doc = doc;

        // Update active tab URL
        if (self.tab_manager.activeTab()) |tab| {
            self.allocator.free(tab.url);
            tab.url = try self.allocator.dupe(u8, effective_url);
        }

        // Record history
        try self.history_store.addVisit(effective_url, "Web Page");
    }

    pub fn handleVimKey(self: *BrowserShell, key: u8) !?VimAction {
        const act = self.vim_controller.handleKey(key);
        if (act) |a| {
            switch (a) {
                .ScrollDown, .ScrollUp, .HalfPageDown, .HalfPageUp, .ScrollTop, .ScrollBottom => {
                    if (self.tab_manager.activeTab()) |tab| {
                        tab.scroll_y = self.vim_controller.scroll_offset_y;
                    }
                },
                .NewTab => |opt_url| {
                    const target = opt_url orelse "about:home";
                    _ = try self.tab_manager.newTab(target, "New Tab", .Default);
                    try self.navigate(target);
                },
                .CloseTab => {
                    if (self.tab_manager.tabs.items.len > 1) {
                        self.tab_manager.closeTab(self.tab_manager.active_index);
                        if (self.tab_manager.activeTab()) |t| {
                            try self.navigate(t.url);
                        }
                    }
                },
                .ActivateTab => |idx| {
                    if (self.tab_manager.activateTab(idx)) {
                        if (self.tab_manager.activeTab()) |t| {
                            try self.navigate(t.url);
                        }
                    }
                },
                .Reload => {
                    if (self.tab_manager.activeTab()) |t| {
                        try self.navigate(t.url);
                    }
                },
                .FollowHint => |data| {
                    if (data.target_url) |u| {
                        if (data.new_tab) {
                            _ = try self.tab_manager.newTab(u, "New Tab", .Default);
                        } else {
                            try self.navigate(u);
                        }
                    }
                },
                .ExecuteCommand => |cmd| {
                    if (std.mem.startsWith(u8, cmd, "http://") or std.mem.startsWith(u8, cmd, "https://") or std.mem.startsWith(u8, cmd, "about:") or std.mem.startsWith(u8, cmd, "file://")) {
                        try self.navigate(cmd);
                    }
                },
                else => {},
            }
        }
        return act;
    }

    pub fn unlockBitwarden(self: *BrowserShell, master_password: []const u8, email: []const u8) !void {
        const crypto = @import("../components/bitwarden/crypto.zig");
        const master_key = try crypto.deriveMasterKey(master_password, email, 5000);
        const keys = crypto.deriveEncryptionKeys(master_key);
        self.vault.unlock(keys);
    }

    pub fn lockBitwarden(self: *BrowserShell) void {
        self.vault.lock();
    }

    pub fn saveBitwardenLogin(self: *BrowserShell, uri: []const u8, username: []const u8, password: []const u8, name: []const u8) !void {
        try self.vault.addCipher(.{
            .id = try self.allocator.dupe(u8, "davoth-item"),
            .cipher_type = .Login,
            .name = try self.allocator.dupe(u8, name),
            .login = .{
                .uri = try self.allocator.dupe(u8, uri),
                .username = try self.allocator.dupe(u8, username),
                .password = try self.allocator.dupe(u8, password),
            },
        });
    }

    pub fn generateBitwardenPassword(self: *BrowserShell, length: usize, upper: bool, lower: bool, nums: bool, syms: bool) ![]u8 {
        const crypto = @import("../components/bitwarden/crypto.zig");
        return crypto.generatePassword(self.allocator, length, upper, lower, nums, syms);
    }

    pub fn autofillActiveTab(self: *BrowserShell) !bool {
        if (!self.vault.is_unlocked) return false;
        const doc = self.current_doc orelse return false;
        const tab = self.tab_manager.activeTab() orelse return false;

        var logins = try self.vault.findLoginsForHost(self.allocator, tab.url);
        defer logins.deinit(self.allocator);

        if (logins.items.len > 0 and logins.items[0].login != null) {
            const form = detectLoginForm(doc, self.atom_table);
            try autofillForm(self.allocator, form, logins.items[0].login.?, self.atom_table);
            return true;
        }
        return false;
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

test "browser shell bitwarden native autofill integration" {
    const allocator = std.testing.allocator;
    const shell = try BrowserShell.init(allocator, 800, 600);
    defer shell.deinit();

    try shell.unlockBitwarden("MasterP@ssword2026!", "user@davoth.org");
    try shell.saveBitwardenLogin("about:home", "admin@davoth.org", "SecretPassword!", "Davoth Admin");

    try shell.navigate("about:home");

    // Verify form was detected and filled
    const doc = shell.current_doc.?;
    const form = detectLoginForm(doc, shell.atom_table);
    try std.testing.expect(form.username_node != null);
    try std.testing.expect(form.password_node != null);

    const val_atom = try shell.atom_table.intern("value");
    try std.testing.expectEqualStrings("admin@davoth.org", form.username_node.?.getAttribute(val_atom).?);
    try std.testing.expectEqualStrings("SecretPassword!", form.password_node.?.getAttribute(val_atom).?);

    // Verify password generator works through shell
    const gen_pass = try shell.generateBitwardenPassword(20, true, true, true, true);
    defer allocator.free(gen_pass);
    try std.testing.expectEqual(@as(usize, 20), gen_pass.len);

    // Lock vault
    shell.lockBitwarden();
    try std.testing.expect(!shell.vault.is_unlocked);
}
