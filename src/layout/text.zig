//! Text layout, glyph metrics, and line breaking.
const std = @import("std");

pub const FontMetrics = struct {
    font_size: f32,
    ascent: f32,
    descent: f32,
    line_height: f32,
    char_width: f32,

    pub fn default(font_size: f32) FontMetrics {
        return .{
            .font_size = font_size,
            .ascent = font_size * 0.8,
            .descent = font_size * 0.2,
            .line_height = font_size * 1.2,
            .char_width = font_size * 0.6,
        };
    }

    pub fn measureText(self: FontMetrics, text: []const u8) f32 {
        var count: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            i += len;
            count += 1;
        }
        return @as(f32, @floatFromInt(count)) * self.char_width;
    }
};

pub const TextLine = struct {
    text: []const u8,
    width: f32,
};

pub fn breakLines(allocator: std.mem.Allocator, text: []const u8, max_width: f32, metrics: FontMetrics) ![]TextLine {
    var lines: std.ArrayList(TextLine) = .empty;
    errdefer lines.deinit(allocator);

    if (text.len == 0 or max_width <= 0.0) {
        return lines.toOwnedSlice(allocator);
    }

    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        const next_space = std.mem.indexOfScalarPos(u8, text, i, ' ');
        const word_end = next_space orelse text.len;
        const candidate = text[start..word_end];
        const width = metrics.measureText(candidate);

        if (width > max_width and i > start) {
            // Break at previous space
            const line_text = text[start..i];
            const line_w = metrics.measureText(line_text);
            try lines.append(allocator, .{ .text = line_text, .width = line_w });
            while (i < text.len and text[i] == ' ') i += 1;
            start = i;
        } else {
            if (next_space) |sp| {
                i = sp + 1;
            } else {
                i = text.len;
            }
        }
    }

    if (start < text.len) {
        const line_text = text[start..text.len];
        const line_w = metrics.measureText(line_text);
        try lines.append(allocator, .{ .text = line_text, .width = line_w });
    }

    return lines.toOwnedSlice(allocator);
}

test "text measurement and line break" {
    const allocator = std.testing.allocator;
    const metrics = FontMetrics.default(16.0);
    const text = "Davoth is a fast independent browser built in Zig";
    const lines = try breakLines(allocator, text, 150.0, metrics);
    defer allocator.free(lines);

    try std.testing.expect(lines.len >= 2);
}
