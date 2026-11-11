//! Address bar (URL bar) navigation, search engines, and autocomplete.
const std = @import("std");

pub const SearchEngine = enum {
    DuckDuckGo,
    Google,
    SearXNG,

    pub fn formatQuery(self: SearchEngine, allocator: std.mem.Allocator, query: []const u8) ![]u8 {
        return switch (self) {
            .DuckDuckGo => std.fmt.allocPrint(allocator, "https://duckduckgo.com/?q={s}", .{query}),
            .Google => std.fmt.allocPrint(allocator, "https://www.google.com/search?q={s}", .{query}),
            .SearXNG => std.fmt.allocPrint(allocator, "https://searx.be/search?q={s}", .{query}),
        };
    }
};

pub const UrlBar = struct {
    pub fn parseInput(allocator: std.mem.Allocator, input: []const u8, engine: SearchEngine) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "http://") or
            std.mem.startsWith(u8, trimmed, "https://") or
            std.mem.startsWith(u8, trimmed, "about:") or
            std.mem.startsWith(u8, trimmed, "file://"))
        {
            return allocator.dupe(u8, trimmed);
        }

        // If it contains a dot and no spaces, treat as domain: e.g. "github.com"
        if (std.mem.indexOfScalar(u8, trimmed, '.') != null and std.mem.indexOfScalar(u8, trimmed, ' ') == null) {
            return std.fmt.allocPrint(allocator, "https://{s}", .{trimmed});
        }

        // Otherwise format as search query
        return engine.formatQuery(allocator, trimmed);
    }
};

test "url bar input parsing" {
    const allocator = std.testing.allocator;
    const url1 = try UrlBar.parseInput(allocator, "https://davoth.org", .DuckDuckGo);
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("https://davoth.org", url1);

    const url2 = try UrlBar.parseInput(allocator, "github.com", .DuckDuckGo);
    defer allocator.free(url2);
    try std.testing.expectEqualStrings("https://github.com", url2);

    const url3 = try UrlBar.parseInput(allocator, "zig programming", .DuckDuckGo);
    defer allocator.free(url3);
    try std.testing.expectEqualStrings("https://duckduckgo.com/?q=zig programming", url3);
}
