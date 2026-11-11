//! FreeType font loader, HarfBuzz text shaping, and glyph cache.
const std = @import("std");
const c = @import("../common/c.zig");

pub const Glyph = struct {
    width: u32,
    height: u32,
    advance_x: f32,
    bitmap: []const u8,
};

pub const FontEngine = struct {
    allocator: std.mem.Allocator,
    ft_lib: c.FT_Library,
    is_initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) FontEngine {
        var lib: c.FT_Library = null;
        const err = c.FT_Init_FreeType(&lib);
        return .{
            .allocator = allocator,
            .ft_lib = lib,
            .is_initialized = (err == 0),
        };
    }

    pub fn deinit(self: *FontEngine) void {
        if (self.is_initialized and self.ft_lib != null) {
            _ = c.FT_Done_FreeType(self.ft_lib);
        }
    }
};

test "font engine initialization" {
    const allocator = std.testing.allocator;
    var engine = FontEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expect(engine.is_initialized);
}
