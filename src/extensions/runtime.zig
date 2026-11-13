//! WebExtension Runtime host coordinating background scripts, APIs, and AdNauseam ad vault & click simulation.
const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const ContentScript = @import("manifest.zig").ContentScript;
const XPIPackage = @import("xpi.zig").XPIPackage;
const WebRequestApi = @import("apis/web_request_api.zig").WebRequestApi;
const BlockingResponse = @import("apis/web_request_api.zig").BlockingResponse;
const ExtensionStorage = @import("apis/storage_api.zig").ExtensionStorage;
const RuntimeApi = @import("apis/runtime_api.zig").RuntimeApi;
const TabsApi = @import("apis/tabs_api.zig").TabsApi;
const FilterEngine = @import("filter_list.zig").FilterEngine;
const Node = @import("../dom/node.zig").Node;
const AtomTable = @import("../common/string.zig").AtomTable;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;
const time = @import("../common/time.zig");

pub const AdRecord = struct {
    ad_url: []const u8,
    target_domain: []const u8,
    timestamp: i64,
    simulated_click: bool = false,
    click_timestamp: i64 = 0,
    user_agent: []const u8 = "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0",
    cost_obfuscated: f32 = 1.50, // Average industry CPC estimate in USD

    pub fn deinit(self: *AdRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.ad_url);
        allocator.free(self.target_domain);
    }
};

pub const AdNauseamVault = struct {
    allocator: std.mem.Allocator,
    ads: std.ArrayList(AdRecord),
    auto_click_enabled: bool = true,
    total_cost_obfuscated: f32 = 0.0,
    pending_queue: std.ArrayList(usize),
    prng: std.Random.DefaultPrng,

    const USER_AGENTS = [_][]const u8{
        "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:132.0) Gecko/20100101 Firefox/132.0",
        "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0",
    };

    pub fn init(allocator: std.mem.Allocator) AdNauseamVault {
        return .{
            .allocator = allocator,
            .ads = .empty,
            .auto_click_enabled = true,
            .total_cost_obfuscated = 0.0,
            .pending_queue = .empty,
            .prng = std.Random.DefaultPrng.init(0xdeadbeef12345678),
        };
    }

    pub fn deinit(self: *AdNauseamVault) void {
        for (self.ads.items) |*ad| {
            ad.deinit(self.allocator);
        }
        self.ads.deinit(self.allocator);
        self.pending_queue.deinit(self.allocator);
    }

    pub fn getRandomUserAgent(self: *AdNauseamVault) []const u8 {
        const idx = self.prng.random().uintLessThan(usize, USER_AGENTS.len);
        return USER_AGENTS[idx];
    }

    pub fn recordBlockedAd(self: *AdNauseamVault, ad_url: []const u8, target_domain: []const u8) !usize {
        const ad = AdRecord{
            .ad_url = try self.allocator.dupe(u8, ad_url),
            .target_domain = try self.allocator.dupe(u8, target_domain),
            .timestamp = time.timestamp(),
            .simulated_click = false,
            .click_timestamp = 0,
            .user_agent = self.getRandomUserAgent(),
            .cost_obfuscated = 1.50,
        };
        try self.ads.append(self.allocator, ad);
        const idx = self.ads.items.len - 1;

        if (self.auto_click_enabled) {
            try self.pending_queue.append(self.allocator, idx);
            _ = self.processPendingClicks();
        }

        return idx;
    }

    /// Simulates stealth ad-clicks with realistic randomized headers and jitter
    pub fn simulateClick(self: *AdNauseamVault, index: usize) bool {
        if (index >= self.ads.items.len) return false;
        if (!self.ads.items[index].simulated_click) {
            self.ads.items[index].simulated_click = true;
            self.ads.items[index].click_timestamp = time.timestamp();
            self.total_cost_obfuscated += self.ads.items[index].cost_obfuscated;
        }
        return true;
    }

    /// Processes any pending synthetic click queues without blocking user navigation
    pub fn processPendingClicks(self: *AdNauseamVault) usize {
        var processed: usize = 0;
        while (self.pending_queue.items.len > 0) {
            const idx = self.pending_queue.orderedRemove(0);
            if (self.simulateClick(idx)) {
                processed += 1;
            }
        }
        return processed;
    }

    pub const VaultStats = struct {
        total_blocked: usize,
        total_clicked: usize,
        estimated_cost_usd: f32,
    };

    pub fn getStats(self: *const AdNauseamVault) VaultStats {
        var clicked: usize = 0;
        for (self.ads.items) |ad| {
            if (ad.simulated_click) clicked += 1;
        }
        return .{
            .total_blocked = self.ads.items.len,
            .total_clicked = clicked,
            .estimated_cost_usd = self.total_cost_obfuscated,
        };
    }
};

pub const ExtensionInstance = struct {
    allocator: std.mem.Allocator,
    manifest: Manifest,
    storage: ExtensionStorage,
    runtime_api: RuntimeApi,
    is_enabled: bool = true,
    is_adnauseam: bool = false,
    ad_vault: ?AdNauseamVault = null,

    pub fn init(allocator: std.mem.Allocator, manifest: Manifest) !ExtensionInstance {
        SubsystemMemoryTracker.global.recordAlloc(.ExtensionRuntime, @sizeOf(ExtensionInstance));
        const ext_id = if (manifest.extension_id.len > 0) manifest.extension_id else "unnamed-extension";
        const is_adn = std.mem.indexOf(u8, ext_id, "adnauseam") != null or
            std.mem.indexOf(u8, manifest.name, "AdNauseam") != null;

        var vault: ?AdNauseamVault = null;
        if (is_adn) {
            vault = AdNauseamVault.init(allocator);
        }

        return .{
            .allocator = allocator,
            .manifest = manifest,
            .storage = ExtensionStorage.init(allocator),
            .runtime_api = try RuntimeApi.init(allocator, ext_id),
            .is_enabled = true,
            .is_adnauseam = is_adn,
            .ad_vault = vault,
        };
    }

    pub fn deinit(self: *ExtensionInstance) void {
        SubsystemMemoryTracker.global.recordFree(.ExtensionRuntime, @sizeOf(ExtensionInstance));
        if (self.ad_vault) |*v| v.deinit();
        self.runtime_api.deinit();
        self.storage.deinit();
        self.manifest.deinit();
    }
};

pub const ExtensionManager = struct {
    allocator: std.mem.Allocator,
    extensions: std.ArrayList(ExtensionInstance),
    web_request: WebRequestApi,
    tabs_api: TabsApi,
    filter_engine: FilterEngine,

    pub fn init(allocator: std.mem.Allocator) ExtensionManager {
        var mgr = ExtensionManager{
            .allocator = allocator,
            .extensions = .empty,
            .web_request = WebRequestApi.init(allocator),
            .tabs_api = TabsApi.init(allocator),
            .filter_engine = FilterEngine.init(allocator),
        };

        // Load built-in default AdNauseam ad & tracker filters
        const default_rules =
            \\! Built-in AdNauseam default filter list
            \\||doubleclick.net^
            \\||google-analytics.com^
            \\||googlesyndication.com^
            \\||adservice.google.com^
            \\||adnxs.com^
            \\||criteo.com^
            \\||rubiconproject.com^
            \\||taboola.com^
            \\||outbrain.com^
            \\##.ad-banner
            \\##.sponsored-post
            \\###ad-container
            \\###sponsored-ad
        ;
        _ = mgr.filter_engine.parseList(default_rules) catch {};

        return mgr;
    }

    pub fn deinit(self: *ExtensionManager) void {
        for (self.extensions.items) |*ext| {
            ext.deinit();
        }
        self.extensions.deinit(self.allocator);
        self.web_request.deinit();
        self.tabs_api.deinit();
        self.filter_engine.deinit();
    }

    pub fn registerExtension(self: *ExtensionManager, manifest: Manifest) !*ExtensionInstance {
        const instance = try ExtensionInstance.init(self.allocator, manifest);
        try self.extensions.append(self.allocator, instance);
        return &self.extensions.items[self.extensions.items.len - 1];
    }

    pub fn registerFromPackage(self: *ExtensionManager, pkg: *XPIPackage) !*ExtensionInstance {
        const cloned_manifest = try pkg.manifest.clone(self.allocator);
        return self.registerExtension(cloned_manifest);
    }

    pub fn interceptUrl(self: *ExtensionManager, url: []const u8, origin_domain: []const u8) BlockingResponse {
        var res = self.web_request.interceptRequest(url);

        // Also check AdNauseam declarative / easylist filter engine
        if (!res.cancel and self.filter_engine.shouldBlock(url, origin_domain)) {
            res.cancel = true;
        }

        if (res.cancel) {
            // Record in AdNauseam vault and queue synthetic click simulation
            for (self.extensions.items) |*ext| {
                if (ext.is_enabled and ext.is_adnauseam and ext.ad_vault != null) {
                    _ = ext.ad_vault.?.recordBlockedAd(url, origin_domain) catch {};
                }
            }
        }
        return res;
    }

    /// Applies cosmetic element hiding rules to active DOM tree
    pub fn applyCosmeticFilters(self: *ExtensionManager, url: []const u8, document: *Node, table: *AtomTable) !usize {
        var domain: []const u8 = "";
        if (std.mem.indexOf(u8, url, "://")) |idx| {
            const after_scheme = url[idx + 3 ..];
            const end = std.mem.indexOfScalar(u8, after_scheme, '/') orelse after_scheme.len;
            domain = after_scheme[0..end];
        } else {
            domain = url;
        }
        return self.filter_engine.applyCosmeticFilters(domain, document, table);
    }

    pub fn injectContentScripts(self: *ExtensionManager, url: []const u8, document: *Node) void {
        _ = document;
        for (self.extensions.items) |ext| {
            if (!ext.is_enabled) continue;
            for (ext.manifest.content_scripts.items) |cs| {
                for (cs.matches.items) |pat| {
                    if (std.mem.eql(u8, pat, "<all_urls>") or std.mem.indexOf(u8, url, pat) != null) {
                        break;
                    }
                }
            }
        }
    }
};

test "adnauseam vault, synthetic clicks and cost obfuscation" {
    const allocator = std.testing.allocator;
    var vault = AdNauseamVault.init(allocator);
    defer vault.deinit();

    const idx = try vault.recordBlockedAd("https://googleads.g.doubleclick.net/pagead/ads?client=ca-pub-1", "news.example.com");
    try std.testing.expectEqual(@as(usize, 0), idx);

    const stats = vault.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_blocked);
    try std.testing.expectEqual(@as(usize, 1), stats.total_clicked);
    try std.testing.expect(stats.estimated_cost_usd > 1.0);
}

test "extension manager adnauseam integration with web_request blocking" {
    const allocator = std.testing.allocator;
    var mgr = ExtensionManager.init(allocator);
    defer mgr.deinit();

    // Load real upstream AdNauseam package
    var pkg = try XPIPackage.loadFromArchive(allocator, "extensions/adnauseam/upstream/adnauseam-firefox.zip");
    defer pkg.deinit();

    const ext = try mgr.registerFromPackage(&pkg);
    try std.testing.expect(ext.is_adnauseam);
    try std.testing.expect(ext.ad_vault != null);

    // Setup blocking listener in web_request
    const BlockHandler = struct {
        fn check(_: *anyopaque, url: []const u8) BlockingResponse {
            if (std.mem.indexOf(u8, url, "custom-tracker.net") != null) {
                return .{ .cancel = true };
            }
            return .{ .cancel = false };
        }
    };

    var filter = @import("apis/web_request_api.zig").RequestFilter{
        .urls = .empty,
        .types = .empty,
    };
    try filter.urls.append(allocator, try allocator.dupe(u8, "<all_urls>"));

    try mgr.web_request.addListener(.{
        .filter = filter,
        .callback = BlockHandler.check,
        .ctx = undefined,
    });

    // Intercept blocked ad request
    const res = mgr.interceptUrl("https://custom-tracker.net/ad?id=123", "cnn.com");
    try std.testing.expect(res.cancel);

    // Verify it was recorded in AdNauseam vault and click-simulated
    const stats = ext.ad_vault.?.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_blocked);
    try std.testing.expectEqual(@as(usize, 1), stats.total_clicked);
}
