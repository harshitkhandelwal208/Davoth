//! WHATWG HTML5 Tree Builder constructing complete DOM tree from tokens.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const AtomTable = @import("../common/string.zig").AtomTable;
const Node = @import("../dom/node.zig").Node;
const HTMLTokenizer = @import("tokenizer.zig").HTMLTokenizer;
const HTMLTokenType = @import("tokenizer.zig").HTMLTokenType;

pub const InsertionMode = enum {
    Initial,
    BeforeHtml,
    BeforeHead,
    InHead,
    AfterHead,
    InBody,
    AfterBody,
    AfterHtml,
};

pub const TreeBuilder = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    tokenizer: HTMLTokenizer,
    mode: InsertionMode = .Initial,
    open_elements: std.ArrayList(*Node),
    document: *Node,

    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable, source: []const u8) !TreeBuilder {
        const doc_atom = try atom_table.intern("#document");
        const doc = try Node.create(allocator, .Document, doc_atom);

        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .tokenizer = HTMLTokenizer.init(source),
            .mode = .Initial,
            .open_elements = .empty,
            .document = doc,
        };
    }

    pub fn deinit(self: *TreeBuilder) void {
        self.open_elements.deinit(self.allocator);
    }

    pub fn parse(self: *TreeBuilder) !*Node {
        while (true) {
            var token = try self.tokenizer.nextToken(self.allocator);
            defer token.deinit(self.allocator);

            if (token.token_type == .EOF) break;

            switch (token.token_type) {
                .DOCTYPE => {
                    self.mode = .BeforeHtml;
                },
                .StartTag => {
                    const tag_lower = try self.allocator.dupe(u8, token.data);
                    defer self.allocator.free(tag_lower);
                    for (tag_lower) |*c| c.* = std.ascii.toLower(c.*);

                    const tag_atom = try self.atom_table.intern(tag_lower);
                    const elem = try Node.create(self.allocator, .Element, tag_atom);

                    // Copy attributes
                    for (token.attributes.items) |attr| {
                        const attr_name_lower = try self.allocator.dupe(u8, attr.name);
                        defer self.allocator.free(attr_name_lower);
                        for (attr_name_lower) |*c| c.* = std.ascii.toLower(c.*);

                        const attr_atom = try self.atom_table.intern(attr_name_lower);
                        try elem.setAttribute(self.allocator, attr_atom, attr.value);
                    }

                    // Hierarchy attachment
                    if (self.open_elements.items.len > 0) {
                        const current = self.open_elements.items[self.open_elements.items.len - 1];
                        try current.appendChild(self.allocator, elem);
                    } else {
                        try self.document.appendChild(self.allocator, elem);
                    }

                    // Void elements do not stay on open_elements stack
                    const is_void = std.mem.eql(u8, tag_lower, "meta") or
                        std.mem.eql(u8, tag_lower, "link") or
                        std.mem.eql(u8, tag_lower, "img") or
                        std.mem.eql(u8, tag_lower, "br") or
                        std.mem.eql(u8, tag_lower, "hr") or
                        std.mem.eql(u8, tag_lower, "input") or
                        token.self_closing;

                    if (!is_void) {
                        try self.open_elements.append(self.allocator, elem);
                    }
                },
                .EndTag => {
                    const tag_lower = try self.allocator.dupe(u8, token.data);
                    defer self.allocator.free(tag_lower);
                    for (tag_lower) |*c| c.* = std.ascii.toLower(c.*);

                    const tag_atom = try self.atom_table.intern(tag_lower);

                    // Pop matching element from stack
                    var i = self.open_elements.items.len;
                    while (i > 0) {
                        i -= 1;
                        if (self.open_elements.items[i].tag_name == tag_atom) {
                            self.open_elements.shrinkRetainingCapacity(i);
                            break;
                        }
                    }
                },
                .Character => {
                    if (self.open_elements.items.len > 0) {
                        const current = self.open_elements.items[self.open_elements.items.len - 1];
                        const text_node = try Node.createText(self.allocator, token.data);
                        try current.appendChild(self.allocator, text_node);
                    }
                },
                .Comment => {
                    const comment_atom = try self.atom_table.intern("#comment");
                    const comment_node = try Node.create(self.allocator, .Comment, comment_atom);
                    comment_node.text_content = try self.allocator.dupe(u8, token.data);
                    if (self.open_elements.items.len > 0) {
                        const current = self.open_elements.items[self.open_elements.items.len - 1];
                        try current.appendChild(self.allocator, comment_node);
                    } else {
                        try self.document.appendChild(self.allocator, comment_node);
                    }
                },
                .EOF => break,
            }
        }

        return self.document;
    }
};

test "tree builder parse html into dom" {
    const allocator = std.testing.allocator;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const html =
        \\<html>
        \\  <head><title>Davoth Test</title></head>
        \\  <body>
        \\    <div id="main" class="content">
        \\      <p>Independent Browser</p>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    var builder = try TreeBuilder.init(allocator, table, html);
    defer builder.deinit();

    const doc = try builder.parse();
    defer doc.deinit(allocator);

    const main_div = doc.getElementById(table, "main");
    try std.testing.expect(main_div != null);
    try std.testing.expectEqualStrings("content", main_div.?.getAttribute(try table.intern("class")).?);
}
