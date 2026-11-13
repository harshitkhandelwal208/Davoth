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
