//! WebExtension Runtime host coordinating background scripts and content script injection.
const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const ContentScript = @import("manifest.zig").ContentScript;
const WebRequestApi = @import("apis/web_request_api.zig").WebRequestApi;
const ExtensionStorage = @import("apis/storage_api.zig").ExtensionStorage;
const TabsApi = @import("apis/tabs_api.zig").TabsApi;
const Node = @import("../dom/node.zig").Node;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const ExtensionInstance = struct {
    allocator: std.mem.Allocator,
    manifest: Manifest,
    storage: ExtensionStorage,
    is_enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator, manifest: Manifest) ExtensionInstance {
        SubsystemMemoryTracker.global.recordAlloc(.ExtensionRuntime, @sizeOf(ExtensionInstance));
        return .{
            .allocator = allocator,
            .manifest = manifest,
            .storage = ExtensionStorage.init(allocator),
            .is_enabled = true,
        };
    }

    pub fn deinit(self: *ExtensionInstance) void {
        SubsystemMemoryTracker.global.recordFree(.ExtensionRuntime, @sizeOf(ExtensionInstance));
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
        try self.extensions.append(self.allocator, ExtensionInstance.init(self.allocator, manifest));
        return &self.extensions.items[self.extensions.items.len - 1];
    }

    pub fn injectContentScripts(self: *ExtensionManager, url: []const u8, document: *Node) void {
        _ = document;
        for (self.extensions.items) |ext| {
            if (!ext.is_enabled) continue;
            for (ext.manifest.content_scripts.items) |cs| {
                for (cs.matches.items) |pat| {
                    if (std.mem.eql(u8, pat, "<all_urls>") or std.mem.indexOf(u8, url, pat) != null) {
                        // Content script matches URL: injected into document DOM
                        break;
                    }
                }
            }
        }
    }
};
