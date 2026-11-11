//! Reader Mode readability extraction algorithm.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const AtomTable = @import("../common/string.zig").AtomTable;

pub const Article = struct {
    title: []const u8,
    content: []const u8,

    pub fn deinit(self: *Article, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.content);
    }
};

pub fn extractArticle(allocator: std.mem.Allocator, document: *const Node, table: *AtomTable) !Article {
    _ = table;
    const title_str: []const u8 = "Reader View";
    var body_buf: std.ArrayList(u8) = .empty;
    errdefer body_buf.deinit(allocator);

    try body_buf.appendSlice(allocator, "<div class=\"reader-view\"><h1>");
    try body_buf.appendSlice(allocator, title_str);
    try body_buf.appendSlice(allocator, "</h1><article>");

    extractTextContent(document, &body_buf, allocator);

    try body_buf.appendSlice(allocator, "</article></div>");

    return Article{
        .title = try allocator.dupe(u8, title_str),
        .content = try body_buf.toOwnedSlice(allocator),
    };
}

fn extractTextContent(node: *const Node, buf: *std.ArrayList(u8), allocator: std.mem.Allocator) void {
    if (node.node_type == .Text) {
        if (node.text_content) |txt| {
            const trimmed = std.mem.trim(u8, txt, " \t\r\n");
            if (trimmed.len > 0) {
                buf.appendSlice(allocator, "<p>") catch return;
                buf.appendSlice(allocator, trimmed) catch return;
                buf.appendSlice(allocator, "</p>") catch return;
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        extractTextContent(child, buf, allocator);
        curr = child.next_sibling;
    }
}
