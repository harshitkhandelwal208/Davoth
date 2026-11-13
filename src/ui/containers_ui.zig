//! Multi-Account Container Visual UI and Partition Isolation Subsystem.
//! Implements Firefox-parity visual indicators (colored top-strips, container badges, icons)
//! and strict isolated storage & cookie partitions per container identity.

const std = @import("std");
const tabs = @import("tabs.zig");
const ContainerId = tabs.ContainerId;
const CookieJar = @import("../net/cookies.zig").CookieJar;
const Storage = @import("../webapis/storage.zig").Storage;
const URL = @import("../common/url.zig").URL;

pub const ContainerVisualConfig = struct {
    id: ContainerId,
    name: []const u8,
    color_hex: []const u8,
    color_rgb: [3]u8,
    icon_name: []const u8,
    icon_glyph: []const u8,

    pub fn isDefault(self: *const ContainerVisualConfig) bool {
        return self.id == .Default;
    }
};

pub const CONTAINERS = [_]ContainerVisualConfig{
    .{
        .id = .Default,
        .name = "Default",
        .color_hex = "#737373",
        .color_rgb = .{ 115, 115, 115 },
        .icon_name = "globe",
        .icon_glyph = "🌐",
    },
    .{
        .id = .Personal,
        .name = "Personal",
        .color_hex = "#37adff",
        .color_rgb = .{ 55, 173, 255 },
        .icon_name = "fingerprint",
        .icon_glyph = "👤",
    },
    .{
        .id = .Work,
        .name = "Work",
        .color_hex = "#ff7139",
        .color_rgb = .{ 255, 113, 57 },
        .icon_name = "briefcase",
        .icon_glyph = "💼",
    },
    .{
        .id = .Banking,
        .name = "Banking",
        .color_hex = "#54c242",
        .color_rgb = .{ 84, 194, 66 },
        .icon_name = "dollar",
        .icon_glyph = "🏦",
    },
    .{
        .id = .Shopping,
        .name = "Shopping",
        .color_hex = "#ec407a",
        .color_rgb = .{ 236, 64, 122 },
        .icon_name = "cart",
        .icon_glyph = "🛒",
    },
};

pub fn getContainerConfig(id: ContainerId) ContainerVisualConfig {
    const idx = @intFromEnum(id);
    if (idx < CONTAINERS.len) {
        return CONTAINERS[idx];
    }
    return CONTAINERS[0];
}

/// Generates custom CSS styling for tab headers with container color strips and badges
pub fn generateContainerTabCss(allocator: std.mem.Allocator, container: ContainerId) ![]u8 {
    const config = getContainerConfig(container);
    if (config.isDefault()) {
        return allocator.dupe(u8,
            \\.tab {
            \\  border-top: 2px solid transparent;
            \\}
            \\.tab .container-badge {
            \\  display: none;
            \\}
        );
    }

    return std.fmt.allocPrint(allocator,
        \\.tab[data-container="{s}"] {{
        \\  border-top: 2px solid {s};
        \\}}
        \\.tab[data-container="{s}"] .container-badge {{
        \\  display: inline-flex;
        \\  align-items: center;
        \\  gap: 4px;
        \\  padding: 1px 6px;
        \\  font-size: 11px;
        \\  font-weight: 500;
        \\  border-radius: 4px;
        \\  background-color: {s}22;
        \\  color: {s};
        \\  margin-left: 6px;
        \\}}
    , .{
        config.name,
        config.color_hex,
        config.name,
        config.color_hex,
        config.color_hex,
    });
}

/// Renders HTML snippet for a tab's visual indicator badge
pub fn renderTabContainerBadge(allocator: std.mem.Allocator, container: ContainerId) ![]u8 {
    const config = getContainerConfig(container);
    if (config.isDefault()) {
        return allocator.dupe(u8, "");
    }

    return std.fmt.allocPrint(allocator,
        \\<span class="container-badge" style="color: {s}; border-color: {s};" title="{s} Container">
        \\  <span class="container-icon">{s}</span>
        \\  <span class="container-name">{s}</span>
        \\</span>
    , .{
        config.color_hex,
        config.color_hex,
        config.name,
        config.icon_glyph,
        config.name,
    });
}

/// Multi-Account Container Partition Manager.
/// Manages separate cookie jars and local storage partitions for each container identity.
pub const ContainerPartitionManager = struct {
    allocator: std.mem.Allocator,
    cookie_jars: [5]CookieJar,
    // Storage partition map: key is "origin#container_id"
    storage_partitions: std.StringHashMap(*Storage),

    pub fn init(allocator: std.mem.Allocator) ContainerPartitionManager {
        return .{
            .allocator = allocator,
            .cookie_jars = .{
                CookieJar.init(allocator),
                CookieJar.init(allocator),
                CookieJar.init(allocator),
                CookieJar.init(allocator),
                CookieJar.init(allocator),
            },
            .storage_partitions = std.StringHashMap(*Storage).init(allocator),
        };
    }

    pub fn deinit(self: *ContainerPartitionManager) void {
        for (&self.cookie_jars) |*jar| {
            jar.deinit();
        }

        var it = self.storage_partitions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.storage_partitions.deinit();
    }

    /// Obtains the dedicated isolated CookieJar for a given container
    pub fn getCookieJar(self: *ContainerPartitionManager, container: ContainerId) *CookieJar {
        const idx = @intFromEnum(container);
        return &self.cookie_jars[idx];
    }

    /// Obtains or creates the isolated Web Storage partition for (origin, container)
    pub fn getLocalStorage(self: *ContainerPartitionManager, origin: []const u8, container: ContainerId) !*Storage {
        const key = try std.fmt.allocPrint(self.allocator, "{s}#{d}", .{ origin, @intFromEnum(container) });
        defer self.allocator.free(key);

        if (self.storage_partitions.get(key)) |store| {
            return store;
        }

        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        const store = try self.allocator.create(Storage);
        errdefer self.allocator.destroy(store);
        store.* = Storage.init(self.allocator);

        try self.storage_partitions.put(owned_key, store);
        return store;
    }

    /// Clears data for a specific container
    pub fn clearContainerData(self: *ContainerPartitionManager, container: ContainerId) void {
        const idx = @intFromEnum(container);
        self.cookie_jars[idx].deinit();
        self.cookie_jars[idx] = CookieJar.init(self.allocator);

        var to_remove = std.ArrayList([]const u8).empty;
        defer to_remove.deinit(self.allocator);

        var it = self.storage_partitions.iterator();
        const suffix = std.fmt.allocPrint(self.allocator, "#{d}", .{@intFromEnum(container)}) catch return;
        defer self.allocator.free(suffix);

        while (it.next()) |entry| {
            if (std.mem.endsWith(u8, entry.key_ptr.*, suffix)) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch {};
            }
        }

        for (to_remove.items) |rem_key| {
            if (self.storage_partitions.fetchRemove(rem_key)) |entry| {
                entry.value.deinit();
                self.allocator.destroy(entry.value);
                self.allocator.free(entry.key);
            }
        }
    }
};

test "container visual config and css rendering" {
    const allocator = std.testing.allocator;

    const personal = getContainerConfig(.Personal);
    try std.testing.expectEqualStrings("Personal", personal.name);
    try std.testing.expectEqualStrings("#37adff", personal.color_hex);
    try std.testing.expectEqualStrings("👤", personal.icon_glyph);

    const work = getContainerConfig(.Work);
    try std.testing.expectEqualStrings("Work", work.name);
    try std.testing.expectEqualStrings("#ff7139", work.color_hex);
    try std.testing.expectEqualStrings("💼", work.icon_glyph);

    const banking = getContainerConfig(.Banking);
    try std.testing.expectEqualStrings("Banking", banking.name);
    try std.testing.expectEqualStrings("#54c242", banking.color_hex);
    try std.testing.expectEqualStrings("🏦", banking.icon_glyph);

    const shopping = getContainerConfig(.Shopping);
    try std.testing.expectEqualStrings("Shopping", shopping.name);
    try std.testing.expectEqualStrings("#ec407a", shopping.color_hex);
    try std.testing.expectEqualStrings("🛒", shopping.icon_glyph);

    // CSS generation
    const work_css = try generateContainerTabCss(allocator, .Work);
    defer allocator.free(work_css);
    try std.testing.expect(std.mem.indexOf(u8, work_css, "#ff7139") != null);
    try std.testing.expect(std.mem.indexOf(u8, work_css, "border-top: 2px solid") != null);

    // Badge rendering
    const banking_badge = try renderTabContainerBadge(allocator, .Banking);
    defer allocator.free(banking_badge);
    try std.testing.expect(std.mem.indexOf(u8, banking_badge, "Banking Container") != null);
    try std.testing.expect(std.mem.indexOf(u8, banking_badge, "🏦") != null);
}

test "multi-account container cookie and storage partition isolation" {
    const allocator = std.testing.allocator;
    var manager = ContainerPartitionManager.init(allocator);
    defer manager.deinit();

    var url = try URL.parse(allocator, "https://davoth.org/dashboard");
    defer url.deinit();

    // 1. Cookie Jar Isolation
    const personal_jar = manager.getCookieJar(.Personal);
    const work_jar = manager.getCookieJar(.Work);

    try personal_jar.setCookie("user_session=alice_personal_token; Path=/", &url);
    try work_jar.setCookie("user_session=alice_work_corp_token; Path=/", &url);

    const personal_cookie_hdr = (try personal_jar.getCookieHeader(&url)).?;
    defer allocator.free(personal_cookie_hdr);
    try std.testing.expectEqualStrings("user_session=alice_personal_token", personal_cookie_hdr);

    const work_cookie_hdr = (try work_jar.getCookieHeader(&url)).?;
    defer allocator.free(work_cookie_hdr);
    try std.testing.expectEqualStrings("user_session=alice_work_corp_token", work_cookie_hdr);

    // Banking jar should have zero cookies
    const banking_jar = manager.getCookieJar(.Banking);
    const banking_cookie_hdr = try banking_jar.getCookieHeader(&url);
    try std.testing.expect(banking_cookie_hdr == null);

    // 2. Local Storage Partition Isolation
    const personal_store = try manager.getLocalStorage("https://davoth.org", .Personal);
    const work_store = try manager.getLocalStorage("https://davoth.org", .Work);
    const shopping_store = try manager.getLocalStorage("https://davoth.org", .Shopping);

    try personal_store.setItem("cart_items", "0");
    try shopping_store.setItem("cart_items", "42");

    try std.testing.expectEqualStrings("0", personal_store.getItem("cart_items").?);
    try std.testing.expectEqualStrings("42", shopping_store.getItem("cart_items").?);
    try std.testing.expect(work_store.getItem("cart_items") == null);

    // Clear personal container
    manager.clearContainerData(.Personal);
    const cleared_personal_cookie = try personal_jar.getCookieHeader(&url);
    try std.testing.expect(cleared_personal_cookie == null);

    // Work and shopping remain completely unaffected
    try std.testing.expectEqualStrings("42", shopping_store.getItem("cart_items").?);
}
