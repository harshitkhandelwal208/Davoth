//! browser.declarativeNetRequest rule matching engine.
const std = @import("std");

pub const RuleActionType = enum {
    Block,
    Redirect,
    Allow,
    UpgradeScheme,
};

pub const RuleAction = struct {
    action_type: RuleActionType,
    redirect_url: ?[]const u8 = null,
};

pub const RuleCondition = struct {
    url_filter: []const u8,
    is_case_sensitive: bool = false,
};

pub const DNRRule = struct {
    id: u32,
    priority: u32 = 1,
    action: RuleAction,
    condition: RuleCondition,

    pub fn matches(self: *const DNRRule, url: []const u8) bool {
        if (self.condition.url_filter.len == 0) return true;
        return std.mem.indexOf(u8, url, self.condition.url_filter) != null;
    }
};

pub const DeclarativeNetRequestEngine = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(DNRRule),

    pub fn init(allocator: std.mem.Allocator) DeclarativeNetRequestEngine {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    pub fn deinit(self: *DeclarativeNetRequestEngine) void {
        for (self.rules.items) |r| {
            self.allocator.free(r.condition.url_filter);
            if (r.action.redirect_url) |u| self.allocator.free(u);
        }
        self.rules.deinit(self.allocator);
    }

    pub fn addRule(self: *DeclarativeNetRequestEngine, id: u32, action: RuleActionType, filter: []const u8) !void {
        try self.rules.append(self.allocator, .{
            .id = id,
            .priority = 1,
            .action = .{ .action_type = action, .redirect_url = null },
            .condition = .{
                .url_filter = try self.allocator.dupe(u8, filter),
                .is_case_sensitive = false,
            },
        });
    }

    pub fn evaluate(self: *const DeclarativeNetRequestEngine, url: []const u8) ?RuleAction {
        for (self.rules.items) |r| {
            if (r.matches(url)) {
                return r.action;
            }
        }
        return null;
    }
};

test "declarative net request rule matching" {
    const allocator = std.testing.allocator;
    var dnr = DeclarativeNetRequestEngine.init(allocator);
    defer dnr.deinit();

    try dnr.addRule(1, .Block, "tracker.analytics.com");
    const act = dnr.evaluate("https://tracker.analytics.com/event");
    try std.testing.expect(act != null);
    try std.testing.expectEqual(RuleActionType.Block, act.?.action_type);
}
