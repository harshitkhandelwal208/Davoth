//! Core geometric and primitive types for Davoth browser engine.
const std = @import("std");

pub const Point = struct {
    x: f32,
    y: f32,

    pub const zero = Point{ .x = 0.0, .y = 0.0 };

    pub fn init(x: f32, y: f32) Point {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Point, other: Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Point, other: Point) Point {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
};

pub const Size = struct {
    width: f32,
    height: f32,

    pub const zero = Size{ .width = 0.0, .height = 0.0 };

    pub fn init(width: f32, height: f32) Size {
        return .{ .width = width, .height = height };
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub const zero = Rect{ .x = 0.0, .y = 0.0, .width = 0.0, .height = 0.0 };

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, pt: Point) bool {
        return pt.x >= self.x and pt.x <= (self.x + self.width) and
            pt.y >= self.y and pt.y <= (self.y + self.height);
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn unionWith(self: Rect, other: Rect) Rect {
        if (self.width == 0.0 and self.height == 0.0) return other;
        if (other.width == 0.0 and other.height == 0.0) return self;
        const min_x = @min(self.x, other.x);
        const min_y = @min(self.y, other.y);
        const max_x = @max(self.x + self.width, other.x + other.width);
        const max_y = @max(self.y + self.height, other.y + other.height);
        return .{
            .x = min_x,
            .y = min_y,
            .width = max_x - min_x,
            .height = max_y - min_y,
        };
    }

    pub fn intersectWith(self: Rect, other: Rect) Rect {
        const min_x = @max(self.x, other.x);
        const min_y = @max(self.y, other.y);
        const max_x = @min(self.x + self.width, other.x + other.width);
        const max_y = @min(self.y + self.height, other.y + other.height);
        if (max_x > min_x and max_y > min_y) {
            return .{
                .x = min_x,
                .y = min_y,
                .width = max_x - min_x,
                .height = max_y - min_y,
            };
        }
        return Rect.zero;
    }
};

pub const BoxEdges = struct {
    top: f32 = 0.0,
    right: f32 = 0.0,
    bottom: f32 = 0.0,
    left: f32 = 0.0,

    pub const zero = BoxEdges{};

    pub fn initAll(val: f32) BoxEdges {
        return .{ .top = val, .right = val, .bottom = val, .left = val };
    }

    pub fn initSymmetric(vertical: f32, horizontal: f32) BoxEdges {
        return .{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
    }

    pub fn horizontalTotal(self: BoxEdges) f32 {
        return self.left + self.right;
    }

    pub fn verticalTotal(self: BoxEdges) f32 {
        return self.top + self.bottom;
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };

    pub fn initRgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn initRgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
            (@as(u32, self.r) << 16) |
            (@as(u32, self.g) << 8) |
            @as(u32, self.b);
    }

    pub fn fromU32(val: u32) Color {
        return .{
            .a = @truncate((val >> 24) & 0xFF),
            .r = @truncate((val >> 16) & 0xFF),
            .g = @truncate((val >> 8) & 0xFF),
            .b = @truncate(val & 0xFF),
        };
    }

    pub fn parseHex(str: []const u8) ?Color {
        if (str.len == 0 or str[0] != '#') return null;
        const hex = str[1..];
        if (hex.len == 3) {
            const r = std.fmt.parseInt(u8, hex[0..1], 16) catch return null;
            const g = std.fmt.parseInt(u8, hex[1..2], 16) catch return null;
            const b = std.fmt.parseInt(u8, hex[2..3], 16) catch return null;
            return Color{ .r = r * 17, .g = g * 17, .b = b * 17, .a = 255 };
        } else if (hex.len == 6) {
            const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return null;
            const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return null;
            return Color{ .r = r, .g = g, .b = b, .a = 255 };
        } else if (hex.len == 8) {
            const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return null;
            const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return null;
            const a = std.fmt.parseInt(u8, hex[6..8], 16) catch return null;
            return Color{ .r = r, .g = g, .b = b, .a = a };
        }
        return null;
    }

    pub fn parse(str: []const u8) ?Color {
        const trimmed = std.mem.trim(u8, str, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (trimmed[0] == '#') return parseHex(trimmed);

        // Named CSS colors
        if (std.ascii.eqlIgnoreCase(trimmed, "transparent")) return Color.transparent;
        if (std.ascii.eqlIgnoreCase(trimmed, "black")) return Color.black;
        if (std.ascii.eqlIgnoreCase(trimmed, "white")) return Color.white;
        if (std.ascii.eqlIgnoreCase(trimmed, "red")) return Color.red;
        if (std.ascii.eqlIgnoreCase(trimmed, "green")) return Color.green;
        if (std.ascii.eqlIgnoreCase(trimmed, "blue")) return Color.blue;
        if (std.ascii.eqlIgnoreCase(trimmed, "gray") or std.ascii.eqlIgnoreCase(trimmed, "grey")) return Color.initRgb(128, 128, 128);
        if (std.ascii.eqlIgnoreCase(trimmed, "lightgray") or std.ascii.eqlIgnoreCase(trimmed, "lightgrey")) return Color.initRgb(211, 211, 211);
        if (std.ascii.eqlIgnoreCase(trimmed, "darkgray") or std.ascii.eqlIgnoreCase(trimmed, "darkgrey")) return Color.initRgb(169, 169, 169);
        if (std.ascii.eqlIgnoreCase(trimmed, "yellow")) return Color.initRgb(255, 255, 0);
        if (std.ascii.eqlIgnoreCase(trimmed, "cyan") or std.ascii.eqlIgnoreCase(trimmed, "aqua")) return Color.initRgb(0, 255, 255);
        if (std.ascii.eqlIgnoreCase(trimmed, "magenta") or std.ascii.eqlIgnoreCase(trimmed, "fuchsia")) return Color.initRgb(255, 0, 255);
        if (std.ascii.eqlIgnoreCase(trimmed, "orange")) return Color.initRgb(255, 165, 0);
        if (std.ascii.eqlIgnoreCase(trimmed, "purple")) return Color.initRgb(128, 0, 128);
        if (std.ascii.eqlIgnoreCase(trimmed, "pink")) return Color.initRgb(255, 192, 203);
        if (std.ascii.eqlIgnoreCase(trimmed, "brown")) return Color.initRgb(165, 42, 42);
        if (std.ascii.eqlIgnoreCase(trimmed, "navy")) return Color.initRgb(0, 0, 128);
        if (std.ascii.eqlIgnoreCase(trimmed, "teal")) return Color.initRgb(0, 128, 128);
        if (std.ascii.eqlIgnoreCase(trimmed, "olive")) return Color.initRgb(128, 128, 0);
        if (std.ascii.eqlIgnoreCase(trimmed, "maroon")) return Color.initRgb(128, 0, 0);
        if (std.ascii.eqlIgnoreCase(trimmed, "silver")) return Color.initRgb(192, 192, 192);
        if (std.ascii.eqlIgnoreCase(trimmed, "gold")) return Color.initRgb(255, 215, 0);

        // rgb(...) and rgba(...)
        if (std.mem.startsWith(u8, trimmed, "rgb(") and std.mem.endsWith(u8, trimmed, ")")) {
            const inner = trimmed[4 .. trimmed.len - 1];
            return parseRgbParams(inner, false);
        }
        if (std.mem.startsWith(u8, trimmed, "rgba(") and std.mem.endsWith(u8, trimmed, ")")) {
            const inner = trimmed[5 .. trimmed.len - 1];
            return parseRgbParams(inner, true);
        }

        return null;
    }

    fn parseRgbParams(inner: []const u8, has_alpha: bool) ?Color {
        var it = std.mem.splitScalar(u8, inner, ',');
        const r_str = std.mem.trim(u8, it.next() orelse return null, " \t\r\n");
        const g_str = std.mem.trim(u8, it.next() orelse return null, " \t\r\n");
        const b_str = std.mem.trim(u8, it.next() orelse return null, " \t\r\n");

        const r = std.fmt.parseInt(u8, r_str, 10) catch return null;
        const g = std.fmt.parseInt(u8, g_str, 10) catch return null;
        const b = std.fmt.parseInt(u8, b_str, 10) catch return null;

        var a: u8 = 255;
        if (has_alpha) {
            if (it.next()) |a_str| {
                const a_trimmed = std.mem.trim(u8, a_str, " \t\r\n");
                if (std.fmt.parseFloat(f32, a_trimmed)) |a_flt| {
                    const clamped = @max(0.0, @min(1.0, a_flt));
                    a = @intFromFloat(clamped * 255.0);
                } else |_| {
                    a = std.fmt.parseInt(u8, a_trimmed, 10) catch 255;
                }
            }
        }
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
};

test "color parse hex and u32 roundtrip" {
    const c1 = Color.parseHex("#FF8000").?;
    try std.testing.expectEqual(@as(u8, 255), c1.r);
    try std.testing.expectEqual(@as(u8, 128), c1.g);
    try std.testing.expectEqual(@as(u8, 0), c1.b);
    try std.testing.expectEqual(@as(u8, 255), c1.a);

    const val = c1.toU32();
    const c2 = Color.fromU32(val);
    try std.testing.expectEqual(c1.r, c2.r);
    try std.testing.expectEqual(c1.g, c2.g);
    try std.testing.expectEqual(c1.b, c2.b);
    try std.testing.expectEqual(c1.a, c2.a);

    // CSS named colors
    const red_col = Color.parse("red").?;
    try std.testing.expectEqual(@as(u8, 255), red_col.r);
    try std.testing.expectEqual(@as(u8, 0), red_col.g);
    try std.testing.expectEqual(@as(u8, 0), red_col.b);

    const blue_col = Color.parse("blue").?;
    try std.testing.expectEqual(@as(u8, 255), blue_col.b);

    // CSS rgb and rgba
    const rgb_col = Color.parse("rgb(10, 20, 30)").?;
    try std.testing.expectEqual(@as(u8, 10), rgb_col.r);
    try std.testing.expectEqual(@as(u8, 20), rgb_col.g);
    try std.testing.expectEqual(@as(u8, 30), rgb_col.b);
    try std.testing.expectEqual(@as(u8, 255), rgb_col.a);

    const rgba_col = Color.parse("rgba(100, 150, 200, 0.5)").?;
    try std.testing.expectEqual(@as(u8, 100), rgba_col.r);
    try std.testing.expectEqual(@as(u8, 150), rgba_col.g);
    try std.testing.expectEqual(@as(u8, 200), rgba_col.b);
    try std.testing.expectEqual(@as(u8, 127), rgba_col.a);
}

pub const ContainerId = enum(u8) {
    Default = 0,
    Personal = 1,
    Work = 2,
    Banking = 3,
    Shopping = 4,
};

test "rect contains and intersects" {
    const r1 = Rect.init(10, 10, 100, 100);
    try std.testing.expect(r1.contains(Point.init(50, 50)));
    try std.testing.expect(!r1.contains(Point.init(5, 5)));

    const r2 = Rect.init(50, 50, 100, 100);
    try std.testing.expect(r1.intersects(r2));
    const r3 = Rect.init(200, 200, 50, 50);
    try std.testing.expect(!r1.intersects(r3));
}
