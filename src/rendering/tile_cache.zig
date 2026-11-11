//! 256x256 Tile caching and damage rect tracking for partial repaints.
const std = @import("std");
const Rect = @import("../common/types.zig").Rect;

pub const TILE_SIZE: usize = 256;

pub const Tile = struct {
    col: usize,
    row: usize,
    is_dirty: bool = true,
};

pub const TileCache = struct {
    allocator: std.mem.Allocator,
    width_tiles: usize,
    height_tiles: usize,
    tiles: []Tile,
    damage_rect: Rect = Rect.zero,

    pub fn init(allocator: std.mem.Allocator, doc_width: f32, doc_height: f32) !TileCache {
        const w_tiles = @as(usize, @intFromFloat(@ceil(doc_width / @as(f32, @floatFromInt(TILE_SIZE)))));
        const h_tiles = @as(usize, @intFromFloat(@ceil(doc_height / @as(f32, @floatFromInt(TILE_SIZE)))));
        const total = @max(1, w_tiles * h_tiles);

        const tiles_slice = try allocator.alloc(Tile, total);
        var r: usize = 0;
        var idx: usize = 0;
        while (r < h_tiles) : (r += 1) {
            var c: usize = 0;
            while (c < w_tiles) : (c += 1) {
                tiles_slice[idx] = .{ .col = c, .row = r, .is_dirty = true };
                idx += 1;
            }
        }

        return TileCache{
            .allocator = allocator,
            .width_tiles = w_tiles,
            .height_tiles = h_tiles,
            .tiles = tiles_slice,
            .damage_rect = Rect.init(0, 0, doc_width, doc_height),
        };
    }

    pub fn deinit(self: *TileCache) void {
        self.allocator.free(self.tiles);
    }

    pub fn invalidateRect(self: *TileCache, damage: Rect) void {
        self.damage_rect = self.damage_rect.unionWith(damage);

        const start_col = @as(usize, @intFromFloat(@max(0.0, @floor(damage.x / @as(f32, @floatFromInt(TILE_SIZE))))));
        const end_col = @min(self.width_tiles, @as(usize, @intFromFloat(@ceil((damage.x + damage.width) / @as(f32, @floatFromInt(TILE_SIZE))))));
        const start_row = @as(usize, @intFromFloat(@max(0.0, @floor(damage.y / @as(f32, @floatFromInt(TILE_SIZE))))));
        const end_row = @min(self.height_tiles, @as(usize, @intFromFloat(@ceil((damage.y + damage.height) / @as(f32, @floatFromInt(TILE_SIZE))))));

        var r = start_row;
        while (r < end_row) : (r += 1) {
            var c = start_col;
            while (c < end_col) : (c += 1) {
                const idx = (r * self.width_tiles) + c;
                if (idx < self.tiles.len) {
                    self.tiles[idx].is_dirty = true;
                }
            }
        }
    }

    pub fn clearDirty(self: *TileCache) void {
        for (self.tiles) |*tile| {
            tile.is_dirty = false;
        }
        self.damage_rect = Rect.zero;
    }
};

test "tile cache damage invalidation" {
    const allocator = std.testing.allocator;
    var cache = try TileCache.init(allocator, 1024, 768);
    defer cache.deinit();

    cache.clearDirty();
    try std.testing.expect(!cache.tiles[0].is_dirty);

    cache.invalidateRect(Rect.init(10, 10, 50, 50));
    try std.testing.expect(cache.tiles[0].is_dirty);
}
