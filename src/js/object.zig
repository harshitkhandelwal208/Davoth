//! Object model with Hidden Classes (Shapes), prototype chains, and property descriptors.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const JSValue = @import("value.zig").JSValue;

pub const BuiltinType = enum(u8) {
    Normal,
    Function,
    Array,
    RegExp,
    Date,
    Error,
    Promise,
    Map,
    Set,
    NativeFunction,
};

pub const PropertyFlags = packed struct(u8) {
    writable: bool = true,
    enumerable: bool = true,
    configurable: bool = true,
    is_accessor: bool = false,
    _pad: u4 = 0,
};

pub const PropertyDescriptor = struct {
    atom: AtomId,
    slot_index: u32,
    flags: PropertyFlags = .{},
};

pub const Shape = struct {
    allocator: std.mem.Allocator,
    parent: ?*Shape = null,
    transition_atom: AtomId = AtomId.empty,
    property: ?PropertyDescriptor = null,
    transitions: std.AutoHashMap(AtomId, *Shape),
    property_count: u32 = 0,

    pub fn createRoot(allocator: std.mem.Allocator) !*Shape {
        const shape = try allocator.create(Shape);
        shape.* = .{
            .allocator = allocator,
            .parent = null,
            .transition_atom = AtomId.empty,
            .property = null,
            .transitions = std.AutoHashMap(AtomId, *Shape).init(allocator),
            .property_count = 0,
        };
        return shape;
    }

    pub fn deinit(self: *Shape) void {
        var it = self.transitions.valueIterator();
        while (it.next()) |child| {
            child.*.deinit();
        }
        self.transitions.deinit();
        self.allocator.destroy(self);
    }

    pub fn transitionAdd(self: *Shape, atom: AtomId, flags: PropertyFlags) !*Shape {
        if (self.transitions.get(atom)) |child| {
            return child;
        }

        const new_shape = try self.allocator.create(Shape);
        new_shape.* = .{
            .allocator = self.allocator,
            .parent = self,
            .transition_atom = atom,
            .property = PropertyDescriptor{
                .atom = atom,
                .slot_index = self.property_count,
                .flags = flags,
            },
            .transitions = std.AutoHashMap(AtomId, *Shape).init(self.allocator),
            .property_count = self.property_count + 1,
        };

        try self.transitions.put(atom, new_shape);
        return new_shape;
    }

    pub fn lookup(self: *Shape, atom: AtomId) ?PropertyDescriptor {
        var curr: ?*const Shape = self;
        while (curr) |s| {
            if (s.property) |prop| {
                if (prop.atom == atom) return prop;
            }
            curr = s.parent;
        }
        return null;
    }
};

pub const NativeFn = *const fn (vm_ctx: *anyopaque, this_val: JSValue, args: []const JSValue) anyerror!JSValue;

pub const JSObject = struct {
    shape: *Shape,
    slots: std.ArrayList(JSValue),
    prototype: ?*JSObject = null,
    builtin_type: BuiltinType = .Normal,
    native_fn: ?NativeFn = null,
    native_ctx: ?*anyopaque = null,
    code_block: ?*const anyopaque = null,
    is_marked: bool = false,
    next_gc: ?*JSObject = null,

    pub fn create(allocator: std.mem.Allocator, root_shape: *Shape, proto: ?*JSObject) !*JSObject {
        const obj = try allocator.create(JSObject);
        obj.* = .{
            .shape = root_shape,
            .slots = .empty,
            .prototype = proto,
            .builtin_type = .Normal,
            .native_fn = null,
            .native_ctx = null,
            .code_block = null,
            .is_marked = false,
            .next_gc = null,
        };
        return obj;
    }

    pub fn createFunction(
        allocator: std.mem.Allocator,
        root_shape: *Shape,
        proto: ?*JSObject,
        n_fn: NativeFn,
        ctx: ?*anyopaque,
    ) !*JSObject {
        const obj = try create(allocator, root_shape, proto);
        obj.builtin_type = .NativeFunction;
        obj.native_fn = n_fn;
        obj.native_ctx = ctx;
        return obj;
    }

    pub fn deinit(self: *JSObject, allocator: std.mem.Allocator) void {
        self.slots.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn getProperty(self: *JSObject, atom: AtomId) ?JSValue {
        if (self.shape.lookup(atom)) |prop| {
            if (prop.slot_index < self.slots.items.len) {
                return self.slots.items[prop.slot_index];
            }
        }
        if (self.prototype) |proto| {
            return proto.getProperty(atom);
        }
        return null;
    }

    pub fn setProperty(self: *JSObject, allocator: std.mem.Allocator, atom: AtomId, value: JSValue) !void {
        if (self.shape.lookup(atom)) |prop| {
            if (prop.slot_index < self.slots.items.len) {
                self.slots.items[prop.slot_index] = value;
                return;
            }
        }

        const new_shape = try self.shape.transitionAdd(atom, .{});
        self.shape = new_shape;
        try self.slots.append(allocator, value);
    }

    pub fn hasProperty(self: *JSObject, atom: AtomId) bool {
        return self.getProperty(atom) != null;
    }

    pub fn getPropertyEntries(self: *JSObject, allocator: std.mem.Allocator, out: *std.ArrayList(PropertyEntry)) !void {
        var curr: ?*const Shape = self.shape;
        while (curr) |s| {
            if (s.property) |prop| {
                if (prop.slot_index < self.slots.items.len) {
                    try out.append(allocator, .{
                        .atom = prop.atom,
                        .value = self.slots.items[prop.slot_index],
                    });
                }
            }
            curr = s.parent;
        }
    }
};

pub const PropertyEntry = struct {
    atom: AtomId,
    value: JSValue,
};

test "hidden classes and property resolution" {
    const allocator = std.testing.allocator;
    const root_shape = try Shape.createRoot(allocator);
    defer root_shape.deinit();

    const atom_x = AtomId.fromU32(10);
    const atom_y = AtomId.fromU32(20);

    const obj = try JSObject.create(allocator, root_shape, null);
    defer obj.deinit(allocator);

    try obj.setProperty(allocator, atom_x, JSValue.fromInt32(100));
    try obj.setProperty(allocator, atom_y, JSValue.fromInt32(200));

    try std.testing.expectEqual(@as(i32, 100), obj.getProperty(atom_x).?.toInt32());
    try std.testing.expectEqual(@as(i32, 200), obj.getProperty(atom_y).?.toInt32());
    try std.testing.expect(obj.getProperty(AtomId.fromU32(999)) == null);
}
