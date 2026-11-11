//! Frame compositor coordinating display list rasterization and tile updates.
const std = @import("std");
const DisplayList = @import("display_list.zig").DisplayList;
const DisplayItem = @import("display_list.zig").DisplayItem;
const GraphicsBackend = @import("../graphics/backend.zig").GraphicsBackend;
const TileCache = @import("tile_cache.zig").TileCache;
const Color = @import("../common/types.zig").Color;

pub const Compositor = struct {
    backend: GraphicsBackend,

    pub fn init(backend: GraphicsBackend) Compositor {
        return .{ .backend = backend };
    }

    pub fn composite(self: *Compositor, list: *const DisplayList, tile_cache: ?*TileCache) void {
        self.backend.clear(Color.white);

        for (list.items.items) |item| {
            switch (item) {
                .DrawRect => |r| {
                    self.backend.drawRect(r.rect, r.color);
                },
                .DrawBorder => |b| {
                    self.backend.drawBorder(b.rect, b.widths, b.color);
                },
                .DrawText => |t| {
                    self.backend.drawText(t.text, t.origin, t.font_size, t.color);
                },
                .PushClip => {},
                .PopClip => {},
            }
        }

        if (tile_cache) |tc| {
            tc.clearDirty();
        }

        self.backend.present();
    }
};
