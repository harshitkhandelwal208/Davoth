//! Memory efficiency infrastructure: Subsystem accounting, PSS/USS tracking,
//! SlabAllocator, ArenaAllocator, BoundedCache, and OS memory reclamation.
const std = @import("std");
const posix = std.posix;
const Mutex = @import("sync.zig").Mutex;
const fs = @import("fs.zig");

pub const Subsystem = enum(u8) {
    DOM,
    Layout,
    JSHeap,
    WASMHeap,
    CSS,
    Style,
    RenderDisplayList,
    NetworkCache,
    ImageDecoders,
    Storage,
    ExtensionRuntime,
    Compositor,
    GPU,
    General,
};

pub const SubsystemStats = struct {
    allocated_bytes: usize = 0,
    freed_bytes: usize = 0,
    peak_bytes: usize = 0,
    allocation_count: usize = 0,

    pub fn currentBytes(self: SubsystemStats) usize {
        if (self.allocated_bytes >= self.freed_bytes) {
            return self.allocated_bytes - self.freed_bytes;
        }
        return 0;
    }
};

pub const ProcessMemoryMetrics = struct {
    rss_kb: usize = 0,
    pss_kb: usize = 0,
    uss_kb: usize = 0,
    vmsize_kb: usize = 0,
};

pub const SubsystemMemoryTracker = struct {
    pub const count = @typeInfo(Subsystem).@"enum".field_names.len;
    stats: [count]SubsystemStats = @splat(.{}),
    mutex: Mutex = .{},

    pub var global: SubsystemMemoryTracker = .{};

    pub fn recordAlloc(self: *SubsystemMemoryTracker, sub: Subsystem, bytes: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const idx = @intFromEnum(sub);
        self.stats[idx].allocated_bytes += bytes;
        self.stats[idx].allocation_count += 1;
        const current = self.stats[idx].currentBytes();
        if (current > self.stats[idx].peak_bytes) {
            self.stats[idx].peak_bytes = current;
        }
    }

    pub fn recordFree(self: *SubsystemMemoryTracker, sub: Subsystem, bytes: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const idx = @intFromEnum(sub);
        self.stats[idx].freed_bytes += bytes;
    }

    pub fn getStats(self: *SubsystemMemoryTracker, sub: Subsystem) SubsystemStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats[@intFromEnum(sub)];
    }

    pub fn getTotalCurrentBytes(self: *SubsystemMemoryTracker) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        var total: usize = 0;
        for (self.stats) |s| {
            total += s.currentBytes();
        }
        return total;
    }

    pub fn readProcessMetrics() ProcessMemoryMetrics {
        var metrics = ProcessMemoryMetrics{};
        var buf: [4096]u8 = undefined;
        const bytes_read = fs.readFileToBuffer("/proc/self/status", &buf) catch return metrics;
        const content = buf[0..bytes_read];

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "VmRSS:")) {
                metrics.rss_kb = parseKbLine(line);
            } else if (std.mem.startsWith(u8, line, "VmSize:")) {
                metrics.vmsize_kb = parseKbLine(line);
            }
        }

        // Try reading smaps_rollup for PSS and USS (Unique Set Size)
        if (fs.readFileToBuffer("/proc/self/smaps_rollup", &buf)) |smaps_read| {
            var smaps_lines = std.mem.splitScalar(u8, buf[0..smaps_read], '\n');
            while (smaps_lines.next()) |sline| {
                if (std.mem.startsWith(u8, sline, "Pss:")) {
                    metrics.pss_kb = parseKbLine(sline);
                } else if (std.mem.startsWith(u8, sline, "Private_Clean:") or std.mem.startsWith(u8, sline, "Private_Dirty:")) {
                    metrics.uss_kb += parseKbLine(sline);
                }
            }
        } else |_| {}

        if (metrics.pss_kb == 0) metrics.pss_kb = metrics.rss_kb;
        if (metrics.uss_kb == 0) metrics.uss_kb = metrics.rss_kb;
        return metrics;
    }

    fn parseKbLine(line: []const u8) usize {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        _ = it.next(); // label
        if (it.next()) |val_str| {
            return std.fmt.parseInt(usize, val_str, 10) catch 0;
        }
        return 0;
    }

    /// Advises Linux kernel to immediately reclaim physical pages back to OS
    pub fn releasePagesToOs(ptr: [*]align(4096) u8, len: usize) void {
        const MADV_DONTNEED: c_int = 4;
        _ = posix.system.madvise(@ptrCast(ptr), len, MADV_DONTNEED);
    }

    /// Trims memory arenas and releases unused heap pages back to Linux kernel
    pub fn deflateHeap() void {
        const Libc = struct {
            extern "c" fn malloc_trim(pad: usize) c_int;
        };
        _ = Libc.malloc_trim(0);
    }
};

/// Fixed-size block slab allocator for ultra-low latency, zero fragmentation
pub fn SlabAllocator(comptime BlockSize: usize, comptime BlocksPerPage: usize) type {
    return struct {
        const Self = @This();
        const Page = struct {
            memory: [BlockSize * BlocksPerPage]u8 align(4096) = undefined,
            free_list: [BlocksPerPage]u16 = undefined,
            free_count: u16 = BlocksPerPage,
            next: ?*Page = null,

            fn init(self: *Page) void {
                var i: u16 = 0;
                while (i < BlocksPerPage) : (i += 1) {
                    self.free_list[i] = i;
                }
                self.free_count = BlocksPerPage;
                self.next = null;
            }

            fn allocate(self: *Page) ?*align(@alignOf(u64)) [BlockSize]u8 {
                if (self.free_count == 0) return null;
                self.free_count -= 1;
                const slot = self.free_list[self.free_count];
                const offset = @as(usize, slot) * BlockSize;
                return @ptrCast(@alignCast(self.memory[offset .. offset + BlockSize]));
            }

            fn free(self: *Page, ptr: [*]const u8) bool {
                const start = @intFromPtr(&self.memory[0]);
                const target = @intFromPtr(ptr);
                if (target >= start and target < start + (BlockSize * BlocksPerPage)) {
                    const slot: u16 = @truncate((target - start) / BlockSize);
                    if (self.free_count < BlocksPerPage) {
                        self.free_list[self.free_count] = slot;
                        self.free_count += 1;
                        return true;
                    }
                }
                return false;
            }
        };

        backing_allocator: std.mem.Allocator,
        head_page: ?*Page = null,
        subsystem: Subsystem,

        pub fn init(allocator: std.mem.Allocator, sub: Subsystem) Self {
            return .{
                .backing_allocator = allocator,
                .head_page = null,
                .subsystem = sub,
            };
        }

        pub fn deinit(self: *Self) void {
            var curr = self.head_page;
            while (curr) |p| {
                const next = p.next;
                self.backing_allocator.destroy(p);
                SubsystemMemoryTracker.global.recordFree(self.subsystem, @sizeOf(Page));
                curr = next;
            }
            self.head_page = null;
        }

        pub fn create(self: *Self) !*align(@alignOf(u64)) [BlockSize]u8 {
            var curr = self.head_page;
            while (curr) |p| {
                if (p.allocate()) |blk| {
                    SubsystemMemoryTracker.global.recordAlloc(self.subsystem, BlockSize);
                    return blk;
                }
                curr = p.next;
            }

            // Allocate a new page
            const new_page = try self.backing_allocator.create(Page);
            new_page.init();
            new_page.next = self.head_page;
            self.head_page = new_page;
            SubsystemMemoryTracker.global.recordAlloc(self.subsystem, @sizeOf(Page));

            const blk = new_page.allocate().?;
            SubsystemMemoryTracker.global.recordAlloc(self.subsystem, BlockSize);
            return blk;
        }

        pub fn destroy(self: *Self, ptr: [*]const u8) void {
            var curr = self.head_page;
            while (curr) |p| {
                if (p.free(ptr)) {
                    SubsystemMemoryTracker.global.recordFree(self.subsystem, BlockSize);
                    return;
                }
                curr = p.next;
            }
        }

        /// Deflates completely idle pages back to the Linux kernel via madvise
        pub fn deflate(self: *Self) usize {
            var reclaimed_bytes: usize = 0;
            var curr = self.head_page;
            while (curr) |p| {
                if (p.free_count == BlocksPerPage) {
                    SubsystemMemoryTracker.releasePagesToOs(@ptrCast(&p.memory[0]), BlockSize * BlocksPerPage);
                    reclaimed_bytes += BlockSize * BlocksPerPage;
                }
                curr = p.next;
            }
            return reclaimed_bytes;
        }
    };
}

/// Bounded LRU Cache with explicit byte quota and automatic eviction
pub fn BoundedCache(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Entry = struct {
            key: K,
            value: V,
            bytes: usize,
            prev: ?*Entry = null,
            next: ?*Entry = null,
        };

        allocator: std.mem.Allocator,
        map: std.AutoHashMap(K, *Entry),
        head: ?*Entry = null,
        tail: ?*Entry = null,
        max_bytes: usize,
        current_bytes: usize = 0,
        subsystem: Subsystem,

        pub fn init(allocator: std.mem.Allocator, max_bytes: usize, sub: Subsystem) Self {
            return .{
                .allocator = allocator,
                .map = std.AutoHashMap(K, *Entry).init(allocator),
                .max_bytes = max_bytes,
                .subsystem = sub,
            };
        }

        pub fn deinit(self: *Self) void {
            var curr = self.head;
            while (curr) |e| {
                const next = e.next;
                self.allocator.destroy(e);
                curr = next;
            }
            self.map.deinit();
            SubsystemMemoryTracker.global.recordFree(self.subsystem, self.current_bytes);
            self.current_bytes = 0;
        }

        pub fn put(self: *Self, key: K, value: V, size_bytes: usize) !void {
            while (self.current_bytes + size_bytes > self.max_bytes and self.tail != null) {
                self.evictTail();
            }

            if (self.map.get(key)) |existing| {
                const old_bytes = existing.bytes;
                self.current_bytes -= old_bytes;
                existing.value = value;
                existing.bytes = size_bytes;
                self.current_bytes += size_bytes;
                if (size_bytes > old_bytes) {
                    SubsystemMemoryTracker.global.recordAlloc(self.subsystem, size_bytes - old_bytes);
                } else if (old_bytes > size_bytes) {
                    SubsystemMemoryTracker.global.recordFree(self.subsystem, old_bytes - size_bytes);
                }
                self.moveToHead(existing);
                return;
            }

            const entry = try self.allocator.create(Entry);
            entry.* = .{
                .key = key,
                .value = value,
                .bytes = size_bytes,
                .prev = null,
                .next = self.head,
            };

            if (self.head) |h| {
                h.prev = entry;
            }
            self.head = entry;
            if (self.tail == null) {
                self.tail = entry;
            }

            try self.map.put(key, entry);
            self.current_bytes += size_bytes;
            SubsystemMemoryTracker.global.recordAlloc(self.subsystem, size_bytes);
        }

        pub fn get(self: *Self, key: K) ?V {
            if (self.map.get(key)) |entry| {
                self.moveToHead(entry);
                return entry.value;
            }
            return null;
        }

        fn moveToHead(self: *Self, entry: *Entry) void {
            if (self.head == entry) return;
            if (entry.prev) |p| p.next = entry.next;
            if (entry.next) |n| n.prev = entry.prev;
            if (self.tail == entry) self.tail = entry.prev;

            entry.prev = null;
            entry.next = self.head;
            if (self.head) |h| h.prev = entry;
            self.head = entry;
        }

        pub fn trimToSize(self: *Self, target_bytes: usize) usize {
            var evicted: usize = 0;
            while (self.current_bytes > target_bytes and self.tail != null) {
                const b = self.tail.?.bytes;
                self.evictTail();
                evicted += b;
            }
            return evicted;
        }

        fn evictTail(self: *Self) void {
            const old_tail = self.tail orelse return;
            _ = self.map.remove(old_tail.key);
            if (old_tail.prev) |p| {
                p.next = null;
                self.tail = p;
            } else {
                self.head = null;
                self.tail = null;
            }
            self.current_bytes -= old_tail.bytes;
            SubsystemMemoryTracker.global.recordFree(self.subsystem, old_tail.bytes);
            self.allocator.destroy(old_tail);
        }
    };
}

test "subsystem memory tracker" {
    var tracker = SubsystemMemoryTracker{};
    tracker.recordAlloc(.DOM, 1024);
    tracker.recordAlloc(.DOM, 2048);
    const stats1 = tracker.getStats(.DOM);
    try std.testing.expectEqual(@as(usize, 3072), stats1.allocated_bytes);
    try std.testing.expectEqual(@as(usize, 3072), stats1.peak_bytes);

    tracker.recordFree(.DOM, 1024);
    const stats2 = tracker.getStats(.DOM);
    try std.testing.expectEqual(@as(usize, 2048), stats2.currentBytes());
}

test "slab allocator basic" {
    const allocator = std.testing.allocator;
    var slab = SlabAllocator(64, 16).init(allocator, .Layout);
    defer slab.deinit();

    const blk1 = try slab.create();
    const blk2 = try slab.create();
    try std.testing.expect(blk1 != blk2);
    slab.destroy(blk1);
    slab.destroy(blk2);
}

test "bounded cache eviction" {
    const allocator = std.testing.allocator;
    var cache = BoundedCache(u32, u32).init(allocator, 100, .NetworkCache);
    defer cache.deinit();

    try cache.put(1, 100, 40);
    try cache.put(2, 200, 40);
    try std.testing.expectEqual(@as(?u32, 100), cache.get(1));
    // Adding 3rd item (40 bytes) exceeds 100 limit, so LRU (2) gets evicted
    try cache.put(3, 300, 40);
    try std.testing.expect(cache.get(2) == null);
    try std.testing.expectEqual(@as(?u32, 100), cache.get(1));
    try std.testing.expectEqual(@as(?u32, 300), cache.get(3));
}

test "slab allocator page deflation and bounded cache trimToSize" {
    const allocator = std.testing.allocator;

    // Test slab allocator deflation
    var slab = SlabAllocator(64, 4).init(allocator, .Layout);
    defer slab.deinit();

    const b1 = try slab.create();
    const b2 = try slab.create();
    slab.destroy(b1);
    slab.destroy(b2);

    const reclaimed = slab.deflate();
    try std.testing.expect(reclaimed >= 64 * 4);

    // Test bounded cache trimToSize
    var cache = BoundedCache(u32, u32).init(allocator, 200, .NetworkCache);
    defer cache.deinit();

    try cache.put(1, 10, 50);
    try cache.put(2, 20, 50);
    try cache.put(3, 30, 50);
    try std.testing.expectEqual(@as(usize, 150), cache.current_bytes);

    const trimmed = cache.trimToSize(60);
    try std.testing.expect(trimmed >= 50);
    try std.testing.expect(cache.current_bytes <= 60);

    // Verify heap deflation call
    SubsystemMemoryTracker.deflateHeap();
}
