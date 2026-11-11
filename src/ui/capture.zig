//! Full-page and viewport screenshot capture.
const std = @import("std");
const SoftwareRasterizer = @import("../graphics/software.zig").SoftwareRasterizer;

pub fn captureViewport(rasterizer: *const SoftwareRasterizer, out_path: []const u8) !void {
    try rasterizer.saveToPpm(out_path);
}
