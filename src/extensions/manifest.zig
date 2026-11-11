//! WebExtension Manifest V2 & V3 parser, validation, and permissions model.
const std = @import("std");

pub const RunAt = enum {
    DocumentStart,
    DocumentEnd,
    DocumentIdle,
};

pub const ContentScript = struct {
    matches: std.ArrayList([]const u8),
    js_files: std.ArrayList([]const u8),
    css_files: std.ArrayList([]const u8),
    run_at: RunAt = .DocumentIdle,
    all_frames: bool = false,

    pub fn deinit(self: *ContentScript, allocator: std.mem.Allocator) void {
        for (self.matches.items) |m| allocator.free(m);
        for (self.js_files.items) |js| allocator.free(js);
        for (self.css_files.items) |css| allocator.free(css);
        self.matches.deinit(allocator);
        self.js_files.deinit(allocator);
        self.css_files.deinit(allocator);
    }
};

pub const Manifest = struct {
    allocator: std.mem.Allocator,
    manifest_version: u8 = 2,
    name: []const u8 = "",
    version: []const u8 = "1.0",
    description: []const u8 = "",
    extension_id: []const u8 = "",

    // Permissions
    permissions: std.ArrayList([]const u8),

    // Background
    background_page: ?[]const u8 = null,
    background_scripts: std.ArrayList([]const u8),

    // Content scripts
    content_scripts: std.ArrayList(ContentScript),

    // Action / Browser action
    popup_path: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, json_text: []const u8) !Manifest {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        var m_version: u8 = 2;
        if (root.get("manifest_version")) |mv| {
            if (mv == .integer) m_version = @truncate(@as(u64, @intCast(mv.integer)));
        }

        const name_val = root.get("name");
        const name_str = if (name_val != null and name_val.? == .string) name_val.?.string else "Extension";

        const ver_val = root.get("version");
        const ver_str = if (ver_val != null and ver_val.? == .string) ver_val.?.string else "1.0";

        var perms: std.ArrayList([]const u8) = .empty;
        errdefer perms.deinit(allocator);

        if (root.get("permissions")) |p_array| {
            if (p_array == .array) {
                for (p_array.array.items) |item| {
                    if (item == .string) {
                        try perms.append(allocator, try allocator.dupe(u8, item.string));
                    }
                }
            }
        }

        var bg_scripts: std.ArrayList([]const u8) = .empty;
        errdefer bg_scripts.deinit(allocator);
        var bg_page: ?[]const u8 = null;

        if (root.get("background")) |bg| {
            if (bg == .object) {
                if (bg.object.get("page")) |page| {
                    if (page == .string) bg_page = try allocator.dupe(u8, page.string);
                }
                if (bg.object.get("scripts")) |scripts| {
                    if (scripts == .array) {
                        for (scripts.array.items) |s| {
                            if (s == .string) {
                                try bg_scripts.append(allocator, try allocator.dupe(u8, s.string));
                            }
                        }
                    }
                }
            }
        }

        // Gecko extension ID
        var ext_id: []const u8 = "";
        if (root.get("browser_specific_settings")) |bss| {
            if (bss == .object) {
                if (bss.object.get("gecko")) |gecko| {
                    if (gecko == .object) {
                        if (gecko.object.get("id")) |id_val| {
                            if (id_val == .string) ext_id = try allocator.dupe(u8, id_val.string);
                        }
                    }
                }
            }
        }

        return Manifest{
            .allocator = allocator,
            .manifest_version = m_version,
            .name = try allocator.dupe(u8, name_str),
            .version = try allocator.dupe(u8, ver_str),
            .description = "",
            .extension_id = ext_id,
            .permissions = perms,
            .background_page = bg_page,
            .background_scripts = bg_scripts,
            .content_scripts = .empty,
            .popup_path = null,
        };
    }

    pub fn deinit(self: *Manifest) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        if (self.extension_id.len > 0) self.allocator.free(self.extension_id);
        for (self.permissions.items) |p| self.allocator.free(p);
        self.permissions.deinit(self.allocator);
        if (self.background_page) |p| self.allocator.free(p);
        for (self.background_scripts.items) |s| self.allocator.free(s);
        self.background_scripts.deinit(self.allocator);
        for (self.content_scripts.items) |*cs| cs.deinit(self.allocator);
        self.content_scripts.deinit(self.allocator);
        if (self.popup_path) |pop| self.allocator.free(pop);
    }

    pub fn hasPermission(self: *const Manifest, perm_name: []const u8) bool {
        for (self.permissions.items) |p| {
            if (std.mem.eql(u8, p, perm_name) or std.mem.eql(u8, p, "<all_urls>")) {
                return true;
            }
        }
        return false;
    }
};

test "parse adnauseam manifest sample" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "manifest_version": 2,
        \\  "name": "AdNauseam",
        \\  "version": "3.29.2",
        \\  "permissions": ["webRequest", "webRequestBlocking", "storage", "tabs"],
        \\  "background": { "page": "background.html" },
        \\  "browser_specific_settings": {
        \\    "gecko": { "id": "adnauseam@rednoise.org" }
        \\  }
        \\}
    ;

    var m = try Manifest.parse(allocator, json);
    defer m.deinit();

    try std.testing.expectEqualStrings("AdNauseam", m.name);
    try std.testing.expectEqualStrings("adnauseam@rednoise.org", m.extension_id);
    try std.testing.expect(m.hasPermission("webRequest"));
    try std.testing.expect(m.hasPermission("storage"));
}
