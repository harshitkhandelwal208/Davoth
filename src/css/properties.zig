//! CSS property values, box-sizing, and ComputedStyle representations.
const std = @import("std");
const Color = @import("../common/types.zig").Color;
const BoxEdges = @import("../common/types.zig").BoxEdges;

pub const Display = enum {
    Block,
    Inline,
    InlineBlock,
    Flex,
    Grid,
    None,
};

pub const Position = enum {
    Static,
    Relative,
    Absolute,
    Fixed,
    Sticky,
};

pub const FlexDirection = enum {
    Row,
    RowReverse,
    Column,
    ColumnReverse,
};

pub const JustifyContent = enum {
    FlexStart,
    FlexEnd,
    Center,
    SpaceBetween,
    SpaceAround,
    SpaceEvenly,
};

pub const AlignItems = enum {
    Stretch,
    FlexStart,
    FlexEnd,
    Center,
    Baseline,
};

pub const BoxSizing = enum {
    ContentBox,
    BorderBox,
};

pub const Unit = enum {
    Px,
    Percent,
    Auto,
};

pub const UnitValue = struct {
    value: f32 = 0.0,
    unit: Unit = .Px,

    pub const auto = UnitValue{ .value = 0.0, .unit = .Auto };
    pub const zero_px = UnitValue{ .value = 0.0, .unit = .Px };

    pub fn px(v: f32) UnitValue {
        return .{ .value = v, .unit = .Px };
    }

    pub fn percent(v: f32) UnitValue {
        return .{ .value = v, .unit = .Percent };
    }

    pub fn resolve(self: UnitValue, container_size: f32) f32 {
        return switch (self.unit) {
            .Px => self.value,
            .Percent => (self.value / 100.0) * container_size,
            .Auto => 0.0,
        };
    }
};

pub const BoxEdgesUnit = struct {
    top: UnitValue = .zero_px,
    right: UnitValue = .zero_px,
    bottom: UnitValue = .zero_px,
    left: UnitValue = .zero_px,

    pub const zero = BoxEdgesUnit{};

    pub fn resolve(self: BoxEdgesUnit, container_w: f32, container_h: f32) BoxEdges {
        return .{
            .top = self.top.resolve(container_h),
            .right = self.right.resolve(container_w),
            .bottom = self.bottom.resolve(container_h),
            .left = self.left.resolve(container_w),
        };
    }
};

pub const ComputedStyle = struct {
    display: Display = .Block,
    position: Position = .Static,
    box_sizing: BoxSizing = .ContentBox,

    // Flexbox
    flex_direction: FlexDirection = .Row,
    justify_content: JustifyContent = .FlexStart,
    align_items: AlignItems = .Stretch,
    flex_grow: f32 = 0.0,
    flex_shrink: f32 = 1.0,
    flex_basis: UnitValue = .auto,

    // Sizing
    width: UnitValue = .auto,
    height: UnitValue = .auto,
    min_width: UnitValue = .zero_px,
    max_width: UnitValue = .auto,
    min_height: UnitValue = .zero_px,
    max_height: UnitValue = .auto,

    // Spacing
    margin: BoxEdgesUnit = .zero,
    padding: BoxEdgesUnit = .zero,
    border_widths: BoxEdges = .zero,

    // Insets
    top: UnitValue = .auto,
    right: UnitValue = .auto,
    bottom: UnitValue = .auto,
    left: UnitValue = .auto,

    // Colors & Typography
    color: Color = Color.black,
    background_color: Color = Color.transparent,
    border_color: Color = Color.black,
    font_size: f32 = 16.0,
    line_height: f32 = 1.2,
    opacity: f32 = 1.0,
    z_index: i32 = 0,
};
