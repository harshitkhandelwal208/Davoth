//! Memory and CPU profiler reporting per-subsystem allocations.
const std = @import("std");
const Subsystem = @import("../common/memory.zig").Subsystem;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const MemoryProfiler = struct {
    pub fn dumpReport() void {
        std.debug.print("=== DAVOTH MEMORY PROFILE REPORT ===\n", .{});
        const metrics = SubsystemMemoryTracker.readProcessMetrics();
        std.debug.print("Process RSS: {d} KB | PSS: {d} KB | USS: {d} KB\n", .{ metrics.rss_kb, metrics.pss_kb, metrics.uss_kb });
        std.debug.print("------------------------------------\n", .{});

        inline for (@typeInfo(Subsystem).@"enum".field_names, @typeInfo(Subsystem).@"enum".field_values) |name, val| {
            const sub: Subsystem = @enumFromInt(val);
            const stats = SubsystemMemoryTracker.global.getStats(sub);
            std.debug.print("{s: <18}: Current: {d: >8} B | Peak: {d: >8} B | Count: {d: >5}\n", .{
                name,
                stats.currentBytes(),
                stats.peak_bytes,
                stats.allocation_count,
            });
        }
        std.debug.print("====================================\n", .{});
    }
};
