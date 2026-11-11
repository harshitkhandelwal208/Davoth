//! browser.webRequest API supporting request interception, blocking, and redirection.
const std = @import("std");

pub const ResourceType = enum {
    MainFrame,
    SubFrame,
    Stylesheet,
    Script,
    Image,
    Font,
    XmlHttpRequest,
    Other,
};

pub const RequestFilter = struct {
    urls: std.ArrayList([]const u8),
    types: std.ArrayList(ResourceType),

    pub fn matches(self: *const RequestFilter, url: []const u8) bool {
        if (self.urls.items.len == 0) return true;
        for (self.urls.items) |pattern| {
            if (std.mem.eql(u8, pattern, "<all_urls>") or std.mem.eql(u8, pattern, "*://*/*")) {
                return true;
            }
            if (std.mem.indexOf(u8, url, pattern)) |_| {
                return true;
            }
        }
        return false;
    }
};

pub const BlockingResponse = struct {
    cancel: bool = false,
    redirect_url: ?[]const u8 = null,
};

pub const WebRequestListener = struct {
    filter: RequestFilter,
    callback: *const fn (ctx: *anyopaque, url: []const u8) BlockingResponse,
    ctx: *anyopaque,
};

pub const WebRequestApi = struct {
    allocator: std.mem.Allocator,
    on_before_request_listeners: std.ArrayList(WebRequestListener),

    pub fn init(allocator: std.mem.Allocator) WebRequestApi {
        return .{
            .allocator = allocator,
            .on_before_request_listeners = .empty,
        };
    }

    pub fn deinit(self: *WebRequestApi) void {
        for (self.on_before_request_listeners.items) |*l| {
            for (l.filter.urls.items) |u| self.allocator.free(u);
            l.filter.urls.deinit(self.allocator);
            l.filter.types.deinit(self.allocator);
        }
        self.on_before_request_listeners.deinit(self.allocator);
    }

    pub fn addListener(self: *WebRequestApi, listener: WebRequestListener) !void {
        try self.on_before_request_listeners.append(self.allocator, listener);
    }

    pub fn interceptRequest(self: *const WebRequestApi, url: []const u8) BlockingResponse {
        for (self.on_before_request_listeners.items) |l| {
            if (l.filter.matches(url)) {
                const res = l.callback(l.ctx, url);
                if (res.cancel or res.redirect_url != null) {
                    return res;
                }
            }
        }
        return .{ .cancel = false, .redirect_url = null };
    }
};

test "web request interception and blocking" {
    const allocator = std.testing.allocator;
    var api = WebRequestApi.init(allocator);
    defer api.deinit();

    var filter = RequestFilter{
        .urls = .empty,
        .types = .empty,
    };
    try filter.urls.append(allocator, try allocator.dupe(u8, "doubleclick.net"));

    const Handler = struct {
        fn blockAd(_: *anyopaque, _: []const u8) BlockingResponse {
            return .{ .cancel = true };
        }
    };

    try api.addListener(.{
        .filter = filter,
        .callback = Handler.blockAd,
        .ctx = undefined,
    });

    const res1 = api.interceptRequest("https://ad.doubleclick.net/tracker.js");
    try std.testing.expect(res1.cancel);

    const res2 = api.interceptRequest("https://davoth.org/index.html");
    try std.testing.expect(!res2.cancel);
}
