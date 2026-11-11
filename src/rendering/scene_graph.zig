//! Stacking contexts and scene graph ordering.
const std = @import("std");
const LayoutBox = @import("../layout/box.zig").LayoutBox;

pub const StackingContext = struct {
    box: *const LayoutBox,
    z_index: i32,
    children: std.ArrayList(*StackingContext),

    pub fn init(allocator: std.mem.Allocator, box: *const LayoutBox) !*StackingContext {
        const sc = try allocator.create(StackingContext);
        sc.* = .{
            .box = box,
            .z_index = box.style.z_index,
            .children = .empty,
        };
        return sc;
    }

    pub fn deinit(self: *StackingContext, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn sortChildren(self: *StackingContext) void {
        const Sorter = struct {
            fn lessThan(_: void, a: *StackingContext, b: *StackingContext) bool {
                return a.z_index < b.z_index;
            }
        };
        std.mem.sort(*StackingContext, self.children.items, {}, Sorter.lessThan);
        for (self.children.items) |child| {
            child.sortChildren();
        }
    }
};
