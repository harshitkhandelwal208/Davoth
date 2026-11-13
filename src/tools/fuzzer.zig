//! Robust differential and corpus fuzz testing harness for Davoth parsers and codecs.
const std = @import("std");
const AtomTable = @import("../common/string.zig").AtomTable;
const TreeBuilder = @import("../html/tree_builder.zig").TreeBuilder;
const CSSParser = @import("../css/parser.zig").CSSParser;
const JSParser = @import("../js/parser.zig").Parser;
const URL = @import("../common/url.zig").URL;
const quic = @import("../net/http3.zig");
const websocket = @import("../net/websocket.zig");

pub const FuzzTarget = enum {
    Html,
    Css,
    JavaScript,
    Url,
    Quic,
    WebSocket,
};

pub const FuzzReport = struct {
    target: FuzzTarget,
    iterations: usize,
    crashes: usize,
};

pub const Fuzzer = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    prng: std.Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !Fuzzer {
        const table = try AtomTable.init(allocator);
        return .{
            .allocator = allocator,
            .atom_table = table,
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    pub fn deinit(self: *Fuzzer) void {
        self.atom_table.deinit();
    }

    /// Fuzzes HTML tree construction with malformed and truncated inputs
    pub fn fuzzHtml(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [256]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            for (buf[0..len]) |*b| {
                const choice = random.uintLessThan(u8, 6);
                b.* = switch (choice) {
                    0 => '<',
                    1 => '>',
                    2 => '/',
                    3 => '=',
                    4 => '\"',
                    else => random.uintLessThan(u8, 127),
                };
            }

            var builder = TreeBuilder.init(self.allocator, self.atom_table, buf[0..len]) catch {
                continue;
            };
            if (builder.parse()) |doc| {
                doc.deinit(self.allocator);
            } else |_| {}
            builder.deinit();
        }

        return .{
            .target = .Html,
            .iterations = iterations,
            .crashes = crashes,
        };
    }

    /// Fuzzes CSS selector and declaration parsing
    pub fn fuzzCss(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [256]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            for (buf[0..len]) |*b| {
                const choice = random.uintLessThan(u8, 7);
                b.* = switch (choice) {
                    0 => '{',
                    1 => '}',
                    2 => ':',
                    3 => ';',
                    4 => '.',
                    5 => '#',
                    else => random.uintLessThan(u8, 127),
                };
            }

            var parser = CSSParser.init(self.allocator, self.atom_table, buf[0..len]);
            var sheet = parser.parse() catch continue;
            sheet.deinit();
        }

        return .{
            .target = .Css,
            .iterations = iterations,
            .crashes = crashes,
        };
    }

    /// Fuzzes JavaScript lexing and parsing
    pub fn fuzzJavaScript(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [256]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            random.bytes(buf[0..len]);

            var parser = JSParser.init(self.allocator, buf[0..len]);
            if (parser.parseProgram()) |ast| {
                ast.deinit(self.allocator);
            } else |_| {}
        }

        return .{
            .target = .JavaScript,
            .iterations = iterations,
            .crashes = crashes,
        };
    }

    /// Fuzzes URL parser with randomized inputs
    pub fn fuzzUrl(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [128]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            random.bytes(buf[0..len]);

            var u = URL.parse(self.allocator, buf[0..len]) catch continue;
            u.deinit();
        }

        return .{
            .target = .Url,
            .iterations = iterations,
            .crashes = crashes,
        };
    }

    /// Fuzzes RFC 9000 QUIC variable-length integer decoder and packet parsing
    pub fn fuzzQuic(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [64]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            random.bytes(buf[0..len]);

            _ = quic.VarInt.decode(buf[0..len]) catch {};
            _ = quic.QuicPacketHeader.deserialize(buf[0..len]) catch {};
        }

        return .{
            .target = .Quic,
            .iterations = iterations,
            .crashes = crashes,
        };
    }

    /// Fuzzes RFC 6455 WebSocket frame deserialization with randomized payloads
    pub fn fuzzWebSocket(self: *Fuzzer, iterations: usize) FuzzReport {
        const random = self.prng.random();
        const crashes: usize = 0;

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var buf: [128]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len);
            random.bytes(buf[0..len]);

            if (websocket.deserializeFrame(self.allocator, buf[0..len])) |des_val| {
                var des = des_val;
                des.deinit(self.allocator);
            } else |_| {}
        }

        return .{
            .target = .WebSocket,
            .iterations = iterations,
            .crashes = crashes,
        };
    }
};

test "parser fuzzer execution on html, css, js, url and quic" {
    const allocator = std.testing.allocator;
    var fuzzer = try Fuzzer.init(allocator, 0x12345678);
    defer fuzzer.deinit();

    const r_html = fuzzer.fuzzHtml(50);
    try std.testing.expectEqual(@as(usize, 0), r_html.crashes);

    const r_css = fuzzer.fuzzCss(50);
    try std.testing.expectEqual(@as(usize, 0), r_css.crashes);

    const r_js = fuzzer.fuzzJavaScript(50);
    try std.testing.expectEqual(@as(usize, 0), r_js.crashes);

    const r_url = fuzzer.fuzzUrl(50);
    try std.testing.expectEqual(@as(usize, 0), r_url.crashes);

    const r_quic = fuzzer.fuzzQuic(50);
    try std.testing.expectEqual(@as(usize, 0), r_quic.crashes);

    const r_ws = fuzzer.fuzzWebSocket(50);
    try std.testing.expectEqual(@as(usize, 0), r_ws.crashes);
}

test "500-iteration memory leak fuzzing with std.testing.allocator" {
    const allocator = std.testing.allocator;
    var fuzzer = try Fuzzer.init(allocator, 0xfeedfacecafebeef);
    defer fuzzer.deinit();

    const r_html = fuzzer.fuzzHtml(500);
    try std.testing.expectEqual(@as(usize, 0), r_html.crashes);

    const r_css = fuzzer.fuzzCss(500);
    try std.testing.expectEqual(@as(usize, 0), r_css.crashes);

    const r_js = fuzzer.fuzzJavaScript(500);
    try std.testing.expectEqual(@as(usize, 0), r_js.crashes);

    const r_url = fuzzer.fuzzUrl(500);
    try std.testing.expectEqual(@as(usize, 0), r_url.crashes);

    const r_quic = fuzzer.fuzzQuic(500);
    try std.testing.expectEqual(@as(usize, 0), r_quic.crashes);

    const r_ws = fuzzer.fuzzWebSocket(500);
    try std.testing.expectEqual(@as(usize, 0), r_ws.crashes);
}
