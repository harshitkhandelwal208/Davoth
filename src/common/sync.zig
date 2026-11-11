//! Synchronization primitives for Davoth.
const std = @import("std");

/// Lightweight atomic spin/yield mutex compatible with Zig 0.17.
pub const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),

    pub fn lock(self: *Mutex) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic)) |_| {
            std.Thread.yield() catch {};
        }
    }

    pub fn tryLock(self: *Mutex) bool {
        return self.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null;
    }

    pub fn unlock(self: *Mutex) void {
        self.state.store(0, .release);
    }
};

test "mutex basic lock and unlock" {
    var m: Mutex = .{};
    m.lock();
    try std.testing.expect(!m.tryLock());
    m.unlock();
    try std.testing.expect(m.tryLock());
    m.unlock();
}
