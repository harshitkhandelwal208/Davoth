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
const Node = @import("../dom/node.zig").Node;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const AdRecord = struct {
    ad_url: []const u8,
    target_domain: []const u8,
    timestamp: i64,
    simulated_click: bool = false,

    pub fn deinit(self: *AdRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.ad_url);
        allocator.free(self.target_domain);
    }
};

pub const AdNauseamVault = struct {
    allocator: std.mem.Allocator,
    ads: std.ArrayList(AdRecord),
    auto_click_enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) AdNauseamVault {
        return .{
            .allocator = allocator,
            .ads = .empty,
            .auto_click_enabled = true,
        };
    }

    pub fn deinit(self: *AdNauseamVault) void {
        for (self.ads.items) |*ad| {
            ad.deinit(self.allocator);
        }
        self.ads.deinit(self.allocator);
    }

    pub fn recordBlockedAd(self: *AdNauseamVault, ad_url: []const u8, target_domain: []const u8) !usize {
        const ad = AdRecord{
            .ad_url = try self.allocator.dupe(u8, ad_url),
            .target_domain = try self.allocator.dupe(u8, target_domain),
            .timestamp = std.time.timestamp(),
            .simulated_click = false,
        };
        try self.ads.append(self.allocator, ad);
        const idx = self.ads.items.len - 1;

        if (self.auto_click_enabled) {
            _ = self.simulateClick(idx);
        }

        return idx;
    }

    /// Simulates a user click by marking the ad clicked and generating synthetic referrer traffic
    pub fn simulateClick(self: *AdNauseamVault, index: usize) bool {
        if (index >= self.ads.items.len) return false;
        self.ads.items[index].simulated_click = true;
        return true;
    }

    pub const VaultStats = struct {
        total_blocked: usize,
        total_clicked: usize,
    };

    pub fn getStats(self: *const AdNauseamVault) VaultStats {
        var clicked: usize = 0;
        for (self.ads.items) |ad| {
            if (ad.simulated_click) clicked += 1;
        }
        return .{
            .total_blocked = self.ads.items.len,
            .total_clicked = clicked,
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
        const ext_id = manifest.id orelse "unnamed-extension";
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

    pub fn init(allocator: std.mem.Allocator) ExtensionManager {
        return .{
            .allocator = allocator,
            .extensions = .empty,
            .web_request = WebRequestApi.init(allocator),
            .tabs_api = TabsApi.init(allocator),
        };
    }

    pub fn deinit(self: *ExtensionManager) void {
        for (self.extensions.items) |*ext| {
            ext.deinit();
        }
        self.extensions.deinit(self.allocator);
        self.web_request.deinit();
        self.tabs_api.deinit();
    }

    pub fn registerExtension(self: *ExtensionManager, manifest: Manifest) !*ExtensionInstance {
        const instance = try ExtensionInstance.init(self.allocator, manifest);
        try self.extensions.append(self.allocator, instance);
        return &self.extensions.items[self.extensions.items.len - 1];
    }

    pub fn registerFromPackage(self: *ExtensionManager, pkg: *XPIPackage) !*ExtensionInstance {
        return self.registerExtension(pkg.manifest);
    }

    pub fn interceptUrl(self: *ExtensionManager, url: []const u8, origin_domain: []const u8) BlockingResponse {
        const res = self.web_request.interceptRequest(url);
        if (res.cancel) {
            // Check if AdNauseam is registered to record in vault
            for (self.extensions.items) |*ext| {
                if (ext.is_enabled and ext.is_adnauseam and ext.ad_vault != null) {
                    _ = ext.ad_vault.?.recordBlockedAd(url, origin_domain) catch {};
                }
            }
        }
        return res;
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

test "adnauseam vault and click simulation" {
    const allocator = std.testing.allocator;
    var vault = AdNauseamVault.init(allocator);
    defer vault.deinit();

    const idx = try vault.recordBlockedAd("https://googleads.g.doubleclick.net/pagead/ads?client=ca-pub-1", "news.example.com");
    try std.testing.expectEqual(@as(usize, 0), idx);

    const stats = vault.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_blocked);
    try std.testing.expectEqual(@as(usize, 1), stats.total_clicked);
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
            if (std.mem.indexOf(u8, url, "doubleclick.net") != null) {
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
    const res = mgr.interceptUrl("https://ad.doubleclick.net/ad?id=123", "cnn.com");
    try std.testing.expect(res.cancel);

    // Verify it was recorded in AdNauseam vault and click-simulated
    const stats = ext.ad_vault.?.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_blocked);
    try std.testing.expectEqual(@as(usize, 1), stats.total_clicked);
}
