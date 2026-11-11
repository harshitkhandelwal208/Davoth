//! XMLHttpRequest implementation with readyState transitions.
const std = @import("std");
const HttpClient = @import("../net/http1.zig").HttpClient;

pub const XHRReadyState = enum(u8) {
    Unsent = 0,
    Opened = 1,
    HeadersReceived = 2,
    Loading = 3,
    Done = 4,
};

pub const XMLHttpRequest = struct {
    allocator: std.mem.Allocator,
    client: *HttpClient,
    ready_state: XHRReadyState = .Unsent,
    status: u16 = 0,
    response_text: ?[]const u8 = null,
    method: []const u8 = "GET",
    url: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, client: *HttpClient) XMLHttpRequest {
        return .{
            .allocator = allocator,
            .client = client,
            .ready_state = .Unsent,
            .status = 0,
            .response_text = null,
            .method = "GET",
            .url = null,
        };
    }

    pub fn deinit(self: *XMLHttpRequest) void {
        if (self.response_text) |t| self.allocator.free(t);
        if (self.url) |u| self.allocator.free(u);
    }

    pub fn open(self: *XMLHttpRequest, method: []const u8, url: []const u8) !void {
        self.method = method;
        if (self.url) |u| self.allocator.free(u);
        self.url = try self.allocator.dupe(u8, url);
        self.ready_state = .Opened;
    }

    pub fn send(self: *XMLHttpRequest) !void {
        const u = self.url orelse return error.NotOpened;
        self.ready_state = .Loading;

        var resp = try self.client.get(u);
        defer resp.deinit();

        self.status = resp.status_code;
        self.response_text = try self.allocator.dupe(u8, resp.body);
        self.ready_state = .Done;
    }
};
