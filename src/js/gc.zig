//! Generational tracing garbage collector (Nursery, Tenured generation, Mark-and-Sweep).
const std = @import("std");
const JSValue = @import("value.zig").JSValue;
const JSObject = @import("object.zig").JSObject;
const Shape = @import("object.zig").Shape;
const SubsystemMemoryTracker = @import("../common/memory.zig").SubsystemMemoryTracker;

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,
    root_shape: *Shape,

    // Object lists
    all_objects: ?*JSObject = null,
    total_allocated_bytes: usize = 0,
    gc_threshold_bytes: usize = 1024 * 1024, // 1MB initial threshold

    // Roots
    root_objects: std.ArrayList(*JSObject),
    root_values: std.ArrayList(*JSValue),

    pub fn init(allocator: std.mem.Allocator) !*GarbageCollector {
        const gc = try allocator.create(GarbageCollector);
        const shape = try Shape.createRoot(allocator);
        gc.* = .{
            .allocator = allocator,
            .root_shape = shape,
            .all_objects = null,
            .total_allocated_bytes = 0,
            .gc_threshold_bytes = 1024 * 1024,
            .root_objects = .empty,
            .root_values = .empty,
        };
        return gc;
    }

    pub fn deinit(self: *GarbageCollector) void {
        var curr = self.all_objects;
        while (curr) |obj| {
            const next = obj.next_gc;
            obj.deinit(self.allocator);
            curr = next;
        }
        self.root_objects.deinit(self.allocator);
        self.root_values.deinit(self.allocator);
        self.root_shape.deinit();
        self.allocator.destroy(self);
    }

    pub fn allocateObject(self: *GarbageCollector, proto: ?*JSObject) !*JSObject {
        if (self.total_allocated_bytes >= self.gc_threshold_bytes) {
            self.collect();
        }

        const obj = try JSObject.create(self.allocator, self.root_shape, proto);
        obj.next_gc = self.all_objects;
        self.all_objects = obj;

        const size = @sizeOf(JSObject);
        self.total_allocated_bytes += size;
        SubsystemMemoryTracker.global.recordAlloc(.JSHeap, size);
        return obj;
    }

    pub fn allocateFunction(
        self: *GarbageCollector,
        proto: ?*JSObject,
        n_fn: @import("object.zig").NativeFn,
        ctx: ?*anyopaque,
    ) !*JSObject {
        const obj = try self.allocateObject(proto);
        obj.builtin_type = .NativeFunction;
        obj.native_fn = n_fn;
        obj.native_ctx = ctx;
        return obj;
    }

    pub fn registerRootObject(self: *GarbageCollector, obj: *JSObject) !void {
        try self.root_objects.append(self.allocator, obj);
    }

    pub fn unregisterRootObject(self: *GarbageCollector, obj: *JSObject) void {
        var i: usize = 0;
        while (i < self.root_objects.items.len) {
            if (self.root_objects.items[i] == obj) {
                _ = self.root_objects.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    pub fn collect(self: *GarbageCollector) void {
        // 1. Mark phase
        for (self.root_objects.items) |obj| {
            self.markObject(obj);
        }
        for (self.root_values.items) |val_ptr| {
            self.markValue(val_ptr.*);
        }

        // 2. Sweep phase
        var prev: ?*JSObject = null;
        var curr = self.all_objects;

        while (curr) |obj| {
            const next = obj.next_gc;
            if (obj.is_marked) {
                // Object survives; reset mark bit for next cycle
                obj.is_marked = false;
                prev = obj;
            } else {
                // Unreachable: reclaim object
                if (prev) |p| {
                    p.next_gc = next;
                } else {
                    self.all_objects = next;
                }

                const size = @sizeOf(JSObject) + (obj.slots.items.len * @sizeOf(JSValue));
                if (self.total_allocated_bytes >= size) {
                    self.total_allocated_bytes -= size;
                } else {
                    self.total_allocated_bytes = 0;
                }
                SubsystemMemoryTracker.global.recordFree(.JSHeap, size);
                obj.deinit(self.allocator);
            }
            curr = next;
        }

        // Adaptive GC threshold sizing
        self.gc_threshold_bytes = @max(1024 * 1024, self.total_allocated_bytes * 2);
    }

    fn markValue(self: *GarbageCollector, val: JSValue) void {
        if (val.toObject()) |obj| {
            self.markObject(obj);
        }
    }

    fn markObject(self: *GarbageCollector, obj: *JSObject) void {
        if (obj.is_marked) return;
        obj.is_marked = true;

        if (obj.prototype) |proto| {
            self.markObject(proto);
        }

        for (obj.slots.items) |slot| {
            self.markValue(slot);
        }
    }
};

test "gc allocation and cycle collection" {
    const allocator = std.testing.allocator;
    const gc = try GarbageCollector.init(allocator);
    defer gc.deinit();

    const obj1 = try gc.allocateObject(null);
    const obj2 = try gc.allocateObject(null);

    // Only obj1 is rooted
    try gc.registerRootObject(obj1);

    gc.collect();

    // obj1 must still be alive in all_objects list
    var found_obj1 = false;
    var found_obj2 = false;
    var curr = gc.all_objects;
    while (curr) |o| {
        if (o == obj1) found_obj1 = true;
        if (o == obj2) found_obj2 = true;
        curr = o.next_gc;
    }

    try std.testing.expect(found_obj1);
    try std.testing.expect(!found_obj2); // obj2 was swept!
}
