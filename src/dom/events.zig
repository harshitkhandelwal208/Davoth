//! DOM Level 3 Event dispatch with capturing, target, and bubbling phases.
const std = @import("std");
const AtomId = @import("../common/string.zig").AtomId;
const Node = @import("node.zig").Node;
const EventListener = @import("node.zig").EventListener;

pub const EventPhase = enum(u8) {
    None = 0,
    Capturing = 1,
    AtTarget = 2,
    Bubbling = 3,
};

pub const Event = struct {
    event_type: AtomId,
    target: ?*Node = null,
    current_target: ?*Node = null,
    phase: EventPhase = .None,
    bubbles: bool = true,
    cancelable: bool = true,
    default_prevented: bool = false,
    stop_immediate: bool = false,
    stop_prop: bool = false,

    pub fn preventDefault(self: *Event) void {
        if (self.cancelable) {
            self.default_prevented = true;
        }
    }

    pub fn stopPropagation(self: *Event) void {
        self.stop_prop = true;
    }
};

pub fn dispatchEvent(allocator: std.mem.Allocator, target: *Node, event: *Event) !bool {
    event.target = target;

    // 1. Build dispatch path from root down to target
    var path: std.ArrayList(*Node) = .empty;
    defer path.deinit(allocator);

    var curr: ?*Node = target;
    while (curr) |n| {
        try path.append(allocator, n);
        curr = n.parent_node;
    }

    // Reverse so path[0] is root (Document) and path[path.len - 1] is Target
    std.mem.reverse(*Node, path.items);

    // 2. Capturing phase (from root down to parent of target)
    event.phase = .Capturing;
    if (path.items.len > 1) {
        var i: usize = 0;
        while (i < path.items.len - 1) : (i += 1) {
            const node = path.items[i];
            event.current_target = node;
            invokeListeners(node, event, true);
            if (event.stop_prop) return !event.default_prevented;
        }
    }

    // 3. At-target phase
    event.phase = .AtTarget;
    event.current_target = target;
    invokeListeners(target, event, false);
    invokeListeners(target, event, true);
    if (event.stop_prop) return !event.default_prevented;

    // 4. Bubbling phase (from parent of target up to root)
    if (event.bubbles and path.items.len > 1) {
        event.phase = .Bubbling;
        var i: usize = path.items.len - 1;
        while (i > 0) {
            i -= 1;
            const node = path.items[i];
            event.current_target = node;
            invokeListeners(node, event, false);
            if (event.stop_prop) return !event.default_prevented;
        }
    }

    return !event.default_prevented;
}

fn invokeListeners(node: *Node, event: *Event, capture: bool) void {
    for (node.listeners.items) |listener| {
        if (listener.event_type == event.event_type and listener.use_capture == capture) {
            listener.callback(listener.ctx, @ptrCast(event));
            if (event.stop_immediate) break;
        }
    }
}

test "event dispatch bubbling" {
    const allocator = std.testing.allocator;
    const AtomTable = @import("../common/string.zig").AtomTable;
    const table = try AtomTable.init(allocator);
    defer table.deinit();

    const click_atom = try table.intern("click");
    const parent = try Node.create(allocator, .Element, try table.intern("div"));
    defer parent.deinit(allocator);

    const child = try Node.create(allocator, .Element, try table.intern("button"));
    try parent.appendChild(allocator, child);

    var parent_clicked = false;
    const Handler = struct {
        fn onParentClick(ctx: *anyopaque, _: *anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(ctx));
            flag.* = true;
        }
    };

    try parent.listeners.append(allocator, .{
        .event_type = click_atom,
        .callback = Handler.onParentClick,
        .ctx = &parent_clicked,
        .use_capture = false,
    });

    var ev = Event{
        .event_type = click_atom,
        .bubbles = true,
    };

    const allowed = try dispatchEvent(allocator, child, &ev);
    try std.testing.expect(allowed);
    try std.testing.expect(parent_clicked); // bubbled to parent!
}
