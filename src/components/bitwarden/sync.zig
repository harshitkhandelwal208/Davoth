//! Bitwarden server API synchronization protocol.
const std = @import("std");
const HttpClient = @import("../../net/http1.zig").HttpClient;
const Vault = @import("vault.zig").Vault;

pub const BitwardenSyncClient = struct {
    allocator: std.mem.Allocator,
    server_url: []const u8 = "https://vault.bitwarden.com",
    access_token: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, server_url: []const u8) BitwardenSyncClient {
        return .{
            .allocator = allocator,
            .server_url = server_url,
            .access_token = null,
        };
    }

    pub fn deinit(self: *BitwardenSyncClient) void {
        if (self.access_token) |t| self.allocator.free(t);
    }

    pub fn setAccessToken(self: *BitwardenSyncClient, token: []const u8) !void {
        if (self.access_token) |t| self.allocator.free(t);
        self.access_token = try self.allocator.dupe(u8, token);
    }
};
