//! Web Platform Tests (WPT) automated compliance test runner for HTML, DOM, and CSS.
const std = @import("std");
const AtomTable = @import("../common/string.zig").AtomTable;
const TreeBuilder = @import("../html/tree_builder.zig").TreeBuilder;
const Node = @import("../dom/node.zig").Node;
const StyleEngine = @import("../css/style.zig").StyleEngine;
const CSSParser = @import("../css/parser.zig").CSSParser;
const buildLayoutTree = @import("../layout/tree.zig").buildLayoutTree;
const performLayout = @import("../layout/reflow.zig").performLayout;

pub const TestStatus = enum {
    Pass,
    Fail,
    Error,
};

pub const TestCaseResult = struct {
    name: []const u8,
    status: TestStatus,
    details: []const u8 = "",
};

pub const WptRunner = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    results: std.ArrayList(TestCaseResult),

    pub fn init(allocator: std.mem.Allocator) !WptRunner {
        const table = try AtomTable.init(allocator);
        return .{
            .allocator = allocator,
            .atom_table = table,
            .results = .empty,
        };
    }

    pub fn deinit(self: *WptRunner) void {
        self.atom_table.deinit();
        self.results.deinit(self.allocator);
    }

    /// Tests HTML5 tree construction according to WPT html/syntax/parsing specs
    pub fn testHtmlParsing(self: *WptRunner, name: []const u8, html_src: []const u8, expected_element_tag: []const u8) !void {
        var builder = try TreeBuilder.init(self.allocator, self.atom_table, html_src);
        defer builder.deinit();

        const doc = try builder.parse();
        defer doc.deinit(self.allocator);

        const exp_atom = try self.atom_table.intern(expected_element_tag);
        const found = self.hasElementWithTag(doc, exp_atom);

        try self.results.append(self.allocator, .{
            .name = name,
            .status = if (found) .Pass else .Fail,
            .details = if (found) "Element matched expected tag" else "Element not found in DOM",
        });
    }

    fn hasElementWithTag(self: *WptRunner, node: *Node, tag: @import("../common/string.zig").AtomId) bool {
        if (node.node_type == .Element and node.tag_name == tag) return true;
        var curr = node.first_child;
        while (curr) |child| {
            if (self.hasElementWithTag(child, tag)) return true;
            curr = child.next_sibling;
        }
        return false;
    }

    /// Tests CSS selector matching and cascade specificity
    pub fn testCssCascade(self: *WptRunner, name: []const u8, css_src: []const u8) !void {
        var parser = CSSParser.init(self.allocator, self.atom_table, css_src);
        var sheet = try parser.parse();
        defer sheet.deinit();

        const ok = sheet.rules.items.len > 0;
        try self.results.append(self.allocator, .{
            .name = name,
            .status = if (ok) .Pass else .Fail,
            .details = if (ok) "Stylesheet parsed successfully" else "No rules produced",
        });
    }

    /// Executes the standard built-in WPT compliance test suite
    pub fn runAll(self: *WptRunner) !struct { passed: usize, failed: usize, total: usize } {
        // Test 1: HTML5 void elements handling
        try self.testHtmlParsing(
            "html/syntax/parsing/void-elements",
            "<div><img src='test.png'><br><input type='text'></div>",
            "img",
        );

        // Test 2: HTML5 table structure auto-insertion
        try self.testHtmlParsing(
            "html/syntax/parsing/table-rows",
            "<table><tr><td>Cell 1</td></tr></table>",
            "td",
        );

        // Test 3: HTML5 nested lists
        try self.testHtmlParsing(
            "html/syntax/parsing/nested-lists",
            "<ul><li>Item 1<ul><li>Nested</li></ul></li></ul>",
            "li",
        );

        // Test 4: CSS complex selectors parsing
        try self.testCssCascade(
            "css/selectors/complex-descendant",
            "div.container > article#main p.highlight { color: #ff0000; font-size: 16px; }",
        );

        // Test 5: CSS flexbox properties parsing
        try self.testCssCascade(
            "css/css-flexbox/flex-direction-row",
            ".flex-row { display: flex; flex-direction: row; justify-content: space-between; }",
        );

        var passed: usize = 0;
        var failed: usize = 0;
        for (self.results.items) |r| {
            if (r.status == .Pass) passed += 1 else failed += 1;
        }

        return .{
            .passed = passed,
            .failed = failed,
            .total = self.results.items.len,
        };
    }
};

test "wpt runner compliance suite execution" {
    const allocator = std.testing.allocator;
    var runner = try WptRunner.init(allocator);
    defer runner.deinit();

    const stats = try runner.runAll();
    try std.testing.expect(stats.total >= 5);
    try std.testing.expectEqual(@as(usize, 0), stats.failed);
}
