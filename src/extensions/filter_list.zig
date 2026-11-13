//! EasyList, uBlock Origin, and AdNauseam filter list parser and cosmetic filtering engine.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const AtomTable = @import("../common/string.zig").AtomTable;

pub const FilterType = enum {
    NetworkBlock,
    NetworkException,
    CosmeticHide,
    CosmeticUnhide,
};

pub const NetworkFilter = struct {
    pattern: []const u8,
    is_exception: bool = false,
    is_domain_anchor: bool = false,
    third_party_only: bool = false,
    domain_scope: ?[]const u8 = null,

    pub fn deinit(self: *NetworkFilter, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
        if (self.domain_scope) |d| allocator.free(d);
    }

    pub fn matches(self: *const NetworkFilter, url: []const u8, origin_domain: ?[]const u8) bool {
        if (self.domain_scope) |scope| {
            if (origin_domain == null or !std.mem.eql(u8, origin_domain.?, scope)) {
                return false;
            }
        }

        if (self.is_domain_anchor) {
            // Pattern starts after '||'
            const anchor = self.pattern;
            if (std.mem.indexOf(u8, url, anchor)) |pos| {
                // Check prefix (scheme or dot)
                if (pos > 0 and url[pos - 1] != '/' and url[pos - 1] != '.') {
                    return false;
                }
                const end_pos = pos + anchor.len;
                if (end_pos == url.len or url[end_pos] == '/' or url[end_pos] == ':' or url[end_pos] == '?' or url[end_pos] == '^') {
                    return true;
                }
            }
            return false;
        }

        // Substring matching
        return std.mem.indexOf(u8, url, self.pattern) != null;
    }
};

pub const CosmeticFilter = struct {
    selector: []const u8,
    domain_scope: ?[]const u8 = null,
    is_exception: bool = false,

    pub fn deinit(self: *CosmeticFilter, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        if (self.domain_scope) |d| allocator.free(d);
    }

    pub fn appliesToDomain(self: *const CosmeticFilter, domain: []const u8) bool {
        if (self.domain_scope) |d| {
            return std.mem.eql(u8, d, domain) or std.mem.endsWith(u8, domain, d);
        }
        return true; // Global cosmetic rule
    }
};

pub const FilterEngine = struct {
    allocator: std.mem.Allocator,
    network_filters: std.ArrayList(NetworkFilter),
    cosmetic_filters: std.ArrayList(CosmeticFilter),

    pub fn init(allocator: std.mem.Allocator) FilterEngine {
        return .{
            .allocator = allocator,
            .network_filters = .empty,
            .cosmetic_filters = .empty,
        };
    }

    pub fn deinit(self: *FilterEngine) void {
        for (self.network_filters.items) |*f| {
            f.deinit(self.allocator);
        }
        self.network_filters.deinit(self.allocator);

        for (self.cosmetic_filters.items) |*c| {
            c.deinit(self.allocator);
        }
        self.cosmetic_filters.deinit(self.allocator);
    }

    /// Parses AdNauseam / EasyList formatted filter list text
    pub fn parseList(self: *FilterEngine, content: []const u8) !usize {
        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '!' or line[0] == '[') {
                continue; // Skip comments and section headers
            }

            // Cosmetic element hiding rule: domain##selector or ##selector
            if (std.mem.indexOf(u8, line, "##")) |hash_pos| {
                const domain_part = line[0..hash_pos];
                const selector_part = line[hash_pos + 2 ..];

                var domain_scope: ?[]const u8 = null;
                if (domain_part.len > 0) {
                    domain_scope = try self.allocator.dupe(u8, domain_part);
                }

                try self.cosmetic_filters.append(self.allocator, .{
                    .selector = try self.allocator.dupe(u8, selector_part),
                    .domain_scope = domain_scope,
                    .is_exception = false,
                });
                count += 1;
                continue;
            }

            // Cosmetic unhide exception: domain#@#selector
            if (std.mem.indexOf(u8, line, "#@#")) |hash_pos| {
                const domain_part = line[0..hash_pos];
                const selector_part = line[hash_pos + 3 ..];

                var domain_scope: ?[]const u8 = null;
                if (domain_part.len > 0) {
                    domain_scope = try self.allocator.dupe(u8, domain_part);
                }

                try self.cosmetic_filters.append(self.allocator, .{
                    .selector = try self.allocator.dupe(u8, selector_part),
                    .domain_scope = domain_scope,
                    .is_exception = true,
                });
                count += 1;
                continue;
            }

            // Network filter rules
            var is_exception = false;
            var rule_str = line;

            if (std.mem.startsWith(u8, rule_str, "@@")) {
                is_exception = true;
                rule_str = rule_str[2..];
            }

            var is_domain_anchor = false;
            if (std.mem.startsWith(u8, rule_str, "||")) {
                is_domain_anchor = true;
                rule_str = rule_str[2..];
            }

            // Strip trailing separator '^'
            if (std.mem.endsWith(u8, rule_str, "^")) {
                rule_str = rule_str[0 .. rule_str.len - 1];
            }

            // Check options e.g. $third-party
            var third_party = false;
            var opt_domain: ?[]const u8 = null;

            if (std.mem.indexOfScalar(u8, rule_str, '$')) |dollar_pos| {
                const opts = rule_str[dollar_pos + 1 ..];
                rule_str = rule_str[0..dollar_pos];

                if (std.mem.indexOf(u8, opts, "third-party") != null) {
                    third_party = true;
                }
                if (std.mem.indexOf(u8, opts, "domain=")) |d_pos| {
                    const d_start = d_pos + 7;
                    const d_end = std.mem.indexOfScalarPos(u8, opts, d_start, ',') orelse opts.len;
                    opt_domain = try self.allocator.dupe(u8, opts[d_start..d_end]);
                }
            }

            try self.network_filters.append(self.allocator, .{
                .pattern = try self.allocator.dupe(u8, rule_str),
                .is_exception = is_exception,
                .is_domain_anchor = is_domain_anchor,
                .third_party_only = third_party,
                .domain_scope = opt_domain,
            });
            count += 1;
        }

        return count;
    }

    /// Checks if a network request should be blocked according to AdNauseam rules
    pub fn shouldBlock(self: *const FilterEngine, url: []const u8, origin_domain: ?[]const u8) bool {
        // First check exception whitelist rules
        for (self.network_filters.items) |f| {
            if (f.is_exception and f.matches(url, origin_domain)) {
                return false; // Whitelisted!
            }
        }

        // Then check blocking rules
        for (self.network_filters.items) |f| {
            if (!f.is_exception and f.matches(url, origin_domain)) {
                return true;
            }
        }

        return false;
    }

    /// Hides elements in the DOM tree matching cosmetic rules for the specified domain
    pub fn applyCosmeticFilters(self: *const FilterEngine, domain: []const u8, root_node: *Node, table: *AtomTable) !usize {
        var hidden_count: usize = 0;
        const style_atom = try table.intern("style");
        const class_atom = try table.intern("class");
        const id_atom = try table.intern("id");

        for (self.cosmetic_filters.items) |cf| {
            if (cf.is_exception or !cf.appliesToDomain(domain)) continue;

            const sel = cf.selector;
            hidden_count += try hideMatchingNodes(self.allocator, root_node, sel, style_atom, class_atom, id_atom);
        }

        return hidden_count;
    }
};

fn hideMatchingNodes(
    allocator: std.mem.Allocator,
    node: *Node,
    selector: []const u8,
    style_atom: @import("../common/string.zig").AtomId,
    class_atom: @import("../common/string.zig").AtomId,
    id_atom: @import("../common/string.zig").AtomId,
) !usize {
    var count: usize = 0;

    if (node.node_type == .Element) {
        var matched = false;

        // Class selector e.g. .ad-banner
        if (std.mem.startsWith(u8, selector, ".")) {
            const class_target = selector[1..];
            if (node.getAttribute(class_atom)) |class_val| {
                if (std.mem.indexOf(u8, class_val, class_target) != null) {
                    matched = true;
                }
            }
        } else if (std.mem.startsWith(u8, selector, "#")) {
            // ID selector e.g. #sponsor
            const id_target = selector[1..];
            if (node.getAttribute(id_atom)) |id_val| {
                if (std.mem.eql(u8, id_val, id_target)) {
                    matched = true;
                }
            }
        } else {
            // General attribute or substring match
            if (node.getAttribute(class_atom)) |c| {
                if (std.mem.indexOf(u8, c, selector) != null) matched = true;
            }
            if (node.getAttribute(id_atom)) |i| {
                if (std.mem.indexOf(u8, i, selector) != null) matched = true;
            }
        }

        if (matched) {
            // Set style="display: none;" so CSS cascade and layout engine completely skip rendering
            try node.setAttribute(allocator, style_atom, "display: none;");
            count += 1;
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        count += try hideMatchingNodes(allocator, child, selector, style_atom, class_atom, id_atom);
        curr = child.next_sibling;
    }

    return count;
}

test "filter list parsing and network blocking" {
    const allocator = std.testing.allocator;
    var engine = FilterEngine.init(allocator);
    defer engine.deinit();

    const sample_rules =
        \\! EasyList & AdNauseam test rule definitions
        \\[Adblock Plus 2.0]
        \\||doubleclick.net^
        \\||google-analytics.com^$third-party
        \\@@||adservice.google.com/essential.js
        \\##.sponsored-banner
        \\example.com###sidebar-ad
    ;

    const count = try engine.parseList(sample_rules);
    try std.testing.expectEqual(@as(usize, 5), count);

    // Blocked
    try std.testing.expect(engine.shouldBlock("https://ad.doubleclick.net/pagead/ads", null));
    try std.testing.expect(engine.shouldBlock("https://www.google-analytics.com/analytics.js", null));

    // Whitelisted exception
    try std.testing.expect(!engine.shouldBlock("https://adservice.google.com/essential.js", null));

    // Normal safe URL allowed
    try std.testing.expect(!engine.shouldBlock("https://davoth.org/index.html", null));
}

test "cosmetic element hiding on DOM tree" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    var engine = FilterEngine.init(allocator);
    defer engine.deinit();

    _ = try engine.parseList("##.ad-banner\nexample.org###promo");

    // Construct DOM tree with ad element
    const doc = try Node.create(allocator, .Element, try table.intern("div"));
    defer doc.deinit(allocator);

    const ad_node = try Node.create(allocator, .Element, try table.intern("div"));
    try ad_node.setAttribute(allocator, try table.intern("class"), "ad-banner container");
    try doc.appendChild(allocator, ad_node);

    const safe_node = try Node.create(allocator, .Element, try table.intern("p"));
    try safe_node.setAttribute(allocator, try table.intern("class"), "article-content");
    try doc.appendChild(allocator, safe_node);

    const hidden = try engine.applyCosmeticFilters("example.org", doc, table);
    try std.testing.expectEqual(@as(usize, 1), hidden);

    const style_atom = try table.intern("style");
    try std.testing.expectEqualStrings("display: none;", ad_node.getAttribute(style_atom).?);
    try std.testing.expect(safe_node.getAttribute(style_atom) == null);
}
