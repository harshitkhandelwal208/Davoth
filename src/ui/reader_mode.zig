//! Mozilla Readability-style DOM article content extraction algorithm,
//! distraction-free reader templates (Light, Sepia, Dark themes), typography controls,
//! and reading time estimation.
const std = @import("std");
const Node = @import("../dom/node.zig").Node;
const AtomTable = @import("../common/string.zig").AtomTable;
const AtomId = @import("../common/string.zig").AtomId;

pub const ReaderTheme = enum {
    Light,
    Sepia,
    Dark,
};

pub const ReaderFont = enum {
    SansSerif,
    Serif,
    Monospace,
};

pub const ReaderConfig = struct {
    theme: ReaderTheme = .Dark,
    font: ReaderFont = .Serif,
    font_size_px: u32 = 18,
    column_width_px: u32 = 680,
    line_height: f32 = 1.6,
};

pub const Article = struct {
    title: []const u8,
    byline: ?[]const u8 = null,
    content_html: []const u8,
    word_count: usize = 0,
    reading_time_minutes: u32 = 1,

    pub fn deinit(self: *Article, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        if (self.byline) |b| allocator.free(b);
        allocator.free(self.content_html);
    }
};

pub const ReaderMode = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    config: ReaderConfig = .{},

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable) ReaderMode {
        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .config = .{},
        };
    }

    /// Extracts clean article content, removing boilerplate navigation, headers, footers, and ads
    pub fn extractArticle(self: *ReaderMode, document: *const Node) !Article {
        const title = try self.extractTitle(document);
        errdefer self.allocator.free(title);

        const byline = try self.extractByline(document);
        errdefer if (byline) |b| self.allocator.free(b);

        var article_buf = std.ArrayList(u8).empty;
        errdefer article_buf.deinit(self.allocator);

        var words: usize = 0;
        try self.extractCleanContent(document, &article_buf, &words);

        const reading_mins: u32 = @max(1, @as(u32, @intCast(@divTrunc(words, 200))));

        return Article{
            .title = title,
            .byline = byline,
            .content_html = try article_buf.toOwnedSlice(self.allocator),
            .word_count = words,
            .reading_time_minutes = reading_mins,
        };
    }

    /// Renders the complete distraction-free reader mode webpage HTML
    pub fn renderReaderPage(self: *const ReaderMode, article: *const Article) ![]u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(self.allocator);

        const theme_css = switch (self.config.theme) {
            .Light =>
            \\body { background-color: #ffffff; color: #202124; }
            \\.reader-container { background-color: #ffffff; }
            \\a { color: #1a73e8; }
            ,
            .Sepia =>
            \\body { background-color: #fbf0d9; color: #5f4b32; }
            \\.reader-container { background-color: #fbf0d9; }
            \\a { color: #7f5e39; }
            ,
            .Dark =>
            \\body { background-color: #1e1e2e; color: #cdd6f4; }
            \\.reader-container { background-color: #1e1e2e; }
            \\a { color: #89b4fa; }
            ,
        };

        const font_family = switch (self.config.font) {
            .SansSerif => "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
            .Serif => "Georgia, Cambria, 'Times New Roman', serif",
            .Monospace => "'Fira Code', 'JetBrains Mono', Consolas, monospace",
        };

        const page = try std.fmt.allocPrint(self.allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <meta charset="utf-8">
            \\  <title>{s}</title>
            \\  <style>
            \\    {s}
            \\    body {{
            \\      margin: 0;
            \\      padding: 40px 20px;
            \\      font-family: {s};
            \\      font-size: {d}px;
            \\      line-height: {d:.1};
            \\      display: flex;
            \\      justify-content: center;
            \\    }}
            \\    .reader-container {{
            \\      max-width: {d}px;
            \\      width: 100%;
            \\    }}
            \\    h1.reader-title {{
            \\      font-size: 2em;
            \\      line-height: 1.25;
            \\      margin-bottom: 8px;
            \\    }}
            \\    .reader-meta {{
            \\      font-size: 0.85em;
            \\      opacity: 0.75;
            \\      margin-bottom: 24px;
            \\      border-bottom: 1px solid rgba(128,128,128,0.2);
            \\      padding-bottom: 12px;
            \\    }}
            \\    .reader-content p {{
            \\      margin-bottom: 1.5em;
            \\    }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="reader-container">
            \\    <h1 class="reader-title">{s}</h1>
            \\    <div class="reader-meta">
            \\      <span>📖 {d} min read ({d} words)</span>
            \\      {s}
            \\    </div>
            \\    <div class="reader-content">
            \\      {s}
            \\    </div>
            \\  </div>
            \\</body>
            \\</html>
        ,
            .{
                article.title,
                theme_css,
                font_family,
                self.config.font_size_px,
                self.config.line_height,
                self.config.column_width_px,
                article.title,
                article.reading_time_minutes,
                article.word_count,
                if (article.byline) |b| b else "",
                article.content_html,
            },
        );

        return page;
    }

    fn extractTitle(self: *ReaderMode, document: *const Node) ![]u8 {
        // 1. Look for <h1>
        const h1_atom = try self.atom_table.intern("h1");
        if (findTagNode(document, h1_atom)) |h1| {
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(self.allocator);
            collectRawText(h1, &buf, self.allocator);
            const trimmed = std.mem.trim(u8, buf.items, " \t\r\n");
            if (trimmed.len > 0) return try self.allocator.dupe(u8, trimmed);
        }

        // 2. Look for <title>
        const title_atom = try self.atom_table.intern("title");
        if (findTagNode(document, title_atom)) |t_node| {
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(self.allocator);
            collectRawText(t_node, &buf, self.allocator);
            const trimmed = std.mem.trim(u8, buf.items, " \t\r\n");
            if (trimmed.len > 0) return try self.allocator.dupe(u8, trimmed);
        }

        return try self.allocator.dupe(u8, "Article");
    }

    fn extractByline(self: *ReaderMode, document: *const Node) !?[]u8 {
        const class_atom = try self.atom_table.intern("class");
        const rel_atom = try self.atom_table.intern("rel");

        // Scan for elements with class author/byline or rel=author
        var candidate: ?*const Node = null;
        findAuthorNode(document, class_atom, rel_atom, &candidate);

        if (candidate) |node| {
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(self.allocator);
            collectRawText(node, &buf, self.allocator);
            const trimmed = std.mem.trim(u8, buf.items, " \t\r\n");
            if (trimmed.len > 0) {
                return try std.fmt.allocPrint(self.allocator, "<span> • By {s}</span>", .{trimmed});
            }
        }
        return null;
    }

    fn extractCleanContent(self: *ReaderMode, node: *const Node, buf: *std.ArrayList(u8), words: *usize) !void {
        if (node.node_type == .Element) {
            const tag_str = self.atom_table.get(node.tag_name);

            // Skip clutter, ads, navigation, scripts, footers
            const clutter_tags = [_][]const u8{ "script", "style", "nav", "footer", "header", "aside", "form", "iframe", "noscript" };
            for (clutter_tags) |c| {
                if (std.mem.eql(u8, tag_str, c)) return;
            }

            // Paragraphs and headings
            if (std.mem.eql(u8, tag_str, "p") or std.mem.eql(u8, tag_str, "h2") or std.mem.eql(u8, tag_str, "h3") or std.mem.eql(u8, tag_str, "li")) {
                var p_buf = std.ArrayList(u8).empty;
                defer p_buf.deinit(self.allocator);

                collectRawText(node, &p_buf, self.allocator);
                const trimmed = std.mem.trim(u8, p_buf.items, " \t\r\n");

                // Only retain meaningful paragraphs (> 10 chars)
                if (trimmed.len > 10) {
                    try buf.appendSlice(self.allocator, "<");
                    try buf.appendSlice(self.allocator, tag_str);
                    try buf.appendSlice(self.allocator, ">");
                    try buf.appendSlice(self.allocator, trimmed);
                    try buf.appendSlice(self.allocator, "</");
                    try buf.appendSlice(self.allocator, tag_str);
                    try buf.appendSlice(self.allocator, ">\n");

                    // Count words
                    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
                    while (it.next()) |_| words.* += 1;
                    return;
                }
            }
        }

        var curr = node.first_child;
        while (curr) |child| {
            try self.extractCleanContent(child, buf, words);
            curr = child.next_sibling;
        }
    }
};

fn findTagNode(node: *const Node, tag: AtomId) ?*const Node {
    if (node.node_type == .Element and node.tag_name == tag) return node;
    var curr = node.first_child;
    while (curr) |child| {
        if (findTagNode(child, tag)) |found| return found;
        curr = child.next_sibling;
    }
    return null;
}

fn findAuthorNode(node: *const Node, class_atom: AtomId, rel_atom: AtomId, candidate: *?*const Node) void {
    if (candidate.* != null) return;
    if (node.node_type == .Element) {
        if (node.getAttribute(class_atom)) |class_val| {
            if (std.mem.indexOf(u8, class_val, "author") != null or std.mem.indexOf(u8, class_val, "byline") != null) {
                candidate.* = node;
                return;
            }
        }
        if (node.getAttribute(rel_atom)) |rel_val| {
            if (std.mem.eql(u8, rel_val, "author")) {
                candidate.* = node;
                return;
            }
        }
    }

    var curr = node.first_child;
    while (curr) |child| {
        findAuthorNode(child, class_atom, rel_atom, candidate);
        curr = child.next_sibling;
    }
}

fn collectRawText(node: *const Node, buf: *std.ArrayList(u8), allocator: std.mem.Allocator) void {
    if (node.node_type == .Text) {
        if (node.text_content) |t| {
            buf.appendSlice(allocator, t) catch return;
            buf.appendSlice(allocator, " ") catch return;
        }
    }
    var curr = node.first_child;
    while (curr) |child| {
        collectRawText(child, buf, allocator);
        curr = child.next_sibling;
    }
}

// Backwards compatibility function
pub fn extractArticle(allocator: std.mem.Allocator, document: *const Node, table: *AtomTable) !Article {
    var rm = ReaderMode.init(allocator, table);
    return rm.extractArticle(document);
}

test "reader mode article extraction, clutter removal, and reading time" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    // Construct mock news article with ads and navigation
    const doc = try Node.create(allocator, .Element, try table.intern("div"));
    defer doc.deinit(allocator);

    const title_node = try Node.create(allocator, .Element, try table.intern("h1"));
    const title_text = try Node.createText(allocator, "Davoth Browser Launches High Performance Engine");
    try title_node.appendChild(allocator, title_text);
    try doc.appendChild(allocator, title_node);

    const byline_node = try Node.create(allocator, .Element, try table.intern("span"));
    try byline_node.setAttribute(allocator, try table.intern("class"), "byline author");
    const byline_text = try Node.createText(allocator, "Ada Lovelace");
    try byline_node.appendChild(allocator, byline_text);
    try doc.appendChild(allocator, byline_node);

    // Clutter to be stripped (navigation and ads)
    const nav_node = try Node.create(allocator, .Element, try table.intern("nav"));
    const nav_text = try Node.createText(allocator, "Home | News | Sports");
    try nav_node.appendChild(allocator, nav_text);
    try doc.appendChild(allocator, nav_node);

    const p1 = try Node.create(allocator, .Element, try table.intern("p"));
    const p1_text = try Node.createText(allocator, "Davoth achieves full feature parity with modern browsers while remaining under 20 megabytes base unique set size.");
    try p1.appendChild(allocator, p1_text);
    try doc.appendChild(allocator, p1);

    var rm = ReaderMode.init(allocator, table);
    rm.config.theme = .Sepia;
    rm.config.font = .Serif;

    var article = try rm.extractArticle(doc);
    defer article.deinit(allocator);

    try std.testing.expectEqualStrings("Davoth Browser Launches High Performance Engine", article.title);
    try std.testing.expect(article.byline != null);
    try std.testing.expect(std.mem.indexOf(u8, article.byline.?, "Ada Lovelace") != null);
    try std.testing.expect(std.mem.indexOf(u8, article.content_html, "under 20 megabytes") != null);
    // Verified clutter was excluded
    try std.testing.expect(std.mem.indexOf(u8, article.content_html, "Home | News") == null);
    try std.testing.expect(article.word_count >= 15);

    // Render Reader HTML page
    const page_html = try rm.renderReaderPage(&article);
    defer allocator.free(page_html);

    try std.testing.expect(std.mem.indexOf(u8, page_html, "#fbf0d9") != null); // Sepia theme
    try std.testing.expect(std.mem.indexOf(u8, page_html, "min read") != null);
}
