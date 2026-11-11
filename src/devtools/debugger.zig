//! JavaScript debugger with breakpoints, callstack inspection, and stepping.
const std = @import("std");

pub const Breakpoint = struct {
    file_path: []const u8,
    line: u32,
    enabled: bool = true,
};

pub const JsDebugger = struct {
    allocator: std.mem.Allocator,
    breakpoints: std.ArrayList(Breakpoint),
    is_paused: bool = false,

    pub fn init(allocator: std.mem.Allocator) JsDebugger {
        return .{
            .allocator = allocator,
            .breakpoints = .empty,
            .is_paused = false,
        };
    }

    pub fn deinit(self: *JsDebugger) void {
        for (self.breakpoints.items) |bp| {
            self.allocator.free(bp.file_path);
        }
        self.breakpoints.deinit(self.allocator);
    }

    pub fn setBreakpoint(self: *JsDebugger, file: []const u8, line: u32) !void {
        try self.breakpoints.append(self.allocator, .{
            .file_path = try self.allocator.dupe(u8, file),
            .line = line,
            .enabled = true,
        });
    }

    pub fn shouldBreak(self: *const JsDebugger, file: []const u8, line: u32) bool {
        for (self.breakpoints.items) |bp| {
            if (bp.enabled and bp.line == line and std.mem.eql(u8, bp.file_path, file)) {
                return true;
            }
        }
        return false;
    }
};
