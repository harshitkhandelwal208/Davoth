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

        var content_scripts = std.ArrayList(ContentScript).empty;
        errdefer {
            for (content_scripts.items) |*cs| cs.deinit(allocator);
            content_scripts.deinit(allocator);
        }

        if (root.get("content_scripts")) |cs_val| {
            if (cs_val == .array) {
                for (cs_val.array.items) |cs_entry| {
                    if (cs_entry == .object) {
                        var matches = std.ArrayList([]const u8).empty;
                        errdefer {
                            for (matches.items) |m| allocator.free(m);
                            matches.deinit(allocator);
                        }
                        if (cs_entry.object.get("matches")) |m_val| {
                            if (m_val == .array) {
                                for (m_val.array.items) |m_item| {
                                    if (m_item == .string) {
                                        try matches.append(allocator, try allocator.dupe(u8, m_item.string));
                                    }
                                }
                            }
                        }

                        var js_files = std.ArrayList([]const u8).empty;
                        errdefer {
                            for (js_files.items) |j| allocator.free(j);
                            js_files.deinit(allocator);
                        }
                        if (cs_entry.object.get("js")) |j_val| {
                            if (j_val == .array) {
                                for (j_val.array.items) |j_item| {
                                    if (j_item == .string) {
                                        try js_files.append(allocator, try allocator.dupe(u8, j_item.string));
                                    }
                                }
                            }
                        }

                        var css_files = std.ArrayList([]const u8).empty;
                        errdefer {
                            for (css_files.items) |c| allocator.free(c);
                            css_files.deinit(allocator);
                        }
                        if (cs_entry.object.get("css")) |c_val| {
                            if (c_val == .array) {
                                for (c_val.array.items) |c_item| {
                                    if (c_item == .string) {
                                        try css_files.append(allocator, try allocator.dupe(u8, c_item.string));
                                    }
                                }
                            }
                        }

                        var run_at: RunAt = .DocumentIdle;
                        if (cs_entry.object.get("run_at")) |r_val| {
                            if (r_val == .string) {
                                if (std.mem.eql(u8, r_val.string, "document_start")) run_at = .DocumentStart;
                                if (std.mem.eql(u8, r_val.string, "document_end")) run_at = .DocumentEnd;
                            }
                        }

                        var all_frames = false;
                        if (cs_entry.object.get("all_frames")) |af_val| {
                            if (af_val == .bool) all_frames = af_val.bool;
                        }

                        try content_scripts.append(allocator, .{
                            .matches = matches,
                            .js_files = js_files,
                            .css_files = css_files,
                            .run_at = run_at,
                            .all_frames = all_frames,
                        });
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
            .content_scripts = content_scripts,
            .popup_path = null,
        };
    }

    pub fn clone(self: *const Manifest, allocator: std.mem.Allocator) !Manifest {
        var perms = std.ArrayList([]const u8).empty;
        errdefer {
            for (perms.items) |p| allocator.free(p);
            perms.deinit(allocator);
        }
        for (self.permissions.items) |p| {
            try perms.append(allocator, try allocator.dupe(u8, p));
        }

        var bg_scripts = std.ArrayList([]const u8).empty;
        errdefer {
            for (bg_scripts.items) |s| allocator.free(s);
            bg_scripts.deinit(allocator);
        }
        for (self.background_scripts.items) |s| {
            try bg_scripts.append(allocator, try allocator.dupe(u8, s));
        }

        var c_scripts = std.ArrayList(ContentScript).empty;
        errdefer {
            for (c_scripts.items) |*cs| cs.deinit(allocator);
            c_scripts.deinit(allocator);
        }
        for (self.content_scripts.items) |cs| {
            var matches = std.ArrayList([]const u8).empty;
            for (cs.matches.items) |m| {
                try matches.append(allocator, try allocator.dupe(u8, m));
            }
            var js_list = std.ArrayList([]const u8).empty;
            for (cs.js_files.items) |j| {
                try js_list.append(allocator, try allocator.dupe(u8, j));
            }
            var css_list = std.ArrayList([]const u8).empty;
            for (cs.css_files.items) |c_item| {
                try css_list.append(allocator, try allocator.dupe(u8, c_item));
            }
            try c_scripts.append(allocator, .{
                .matches = matches,
                .js_files = js_list,
                .css_files = css_list,
                .run_at = cs.run_at,
                .all_frames = cs.all_frames,
            });
        }

        return Manifest{
            .allocator = allocator,
            .manifest_version = self.manifest_version,
            .name = try allocator.dupe(u8, self.name),
            .version = try allocator.dupe(u8, self.version),
            .description = self.description,
            .extension_id = if (self.extension_id.len > 0) try allocator.dupe(u8, self.extension_id) else "",
            .permissions = perms,
            .background_page = if (self.background_page) |bp| try allocator.dupe(u8, bp) else null,
            .background_scripts = bg_scripts,
            .content_scripts = c_scripts,
            .popup_path = if (self.popup_path) |p| try allocator.dupe(u8, p) else null,
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
