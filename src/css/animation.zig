//! CSS3 Keyframe Animations and Cubic-Bezier Easing Engine.
//! Implements Newton-Raphson cubic-bezier curve solver, standard easing functions
//! (ease, ease-in, ease-out, ease-in-out, linear), @keyframes parsing,
//! and time-stepped animation sampling with fill modes and alternating directions.

const std = @import("std");
const Color = @import("../common/types.zig").Color;

pub const CubicBezier = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,

    pub const linear = CubicBezier{ .x1 = 0.0, .y1 = 0.0, .x2 = 1.0, .y2 = 1.0 };
    pub const ease = CubicBezier{ .x1 = 0.25, .y1 = 0.1, .x2 = 0.25, .y2 = 1.0 };
    pub const ease_in = CubicBezier{ .x1 = 0.42, .y1 = 0.0, .x2 = 1.0, .y2 = 1.0 };
    pub const ease_out = CubicBezier{ .x1 = 0.0, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };
    pub const ease_in_out = CubicBezier{ .x1 = 0.42, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };

    pub fn init(x1: f32, y1: f32, x2: f32, y2: f32) CubicBezier {
        return .{
            .x1 = std.math.clamp(x1, 0.0, 1.0),
            .y1 = y1,
            .x2 = std.math.clamp(x2, 0.0, 1.0),
            .y2 = y2,
        };
    }

    fn sampleCurveX(self: CubicBezier, t: f32) f32 {
        // ((1 - 3*x2 + 3*x1)*t + (3*x2 - 6*x1))*t + 3*x1) * t
        const c = 3.0 * self.x1;
        const b = 3.0 * (self.x2 - self.x1) - c;
        const a = 1.0 - c - b;
        return ((a * t + b) * t + c) * t;
    }

    fn sampleCurveY(self: CubicBezier, t: f32) f32 {
        const c = 3.0 * self.y1;
        const b = 3.0 * (self.y2 - self.y1) - c;
        const a = 1.0 - c - b;
        return ((a * t + b) * t + c) * t;
    }

    fn sampleCurveDerivativeX(self: CubicBezier, t: f32) f32 {
        const c = 3.0 * self.x1;
        const b = 3.0 * (self.x2 - self.x1) - c;
        const a = 1.0 - c - b;
        return (3.0 * a * t + 2.0 * b) * t + c;
    }

    /// Solves for t given x using Newton-Raphson iteration with bisection fallback
    pub fn solve(self: CubicBezier, x_target: f32) f32 {
        if (x_target <= 0.0) return 0.0;
        if (x_target >= 1.0) return 1.0;

        var t = x_target;
        // First try 8 iterations of Newton-Raphson
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            const x = self.sampleCurveX(t) - x_target;
            if (@abs(x) < 1e-6) return self.sampleCurveY(t);
            const d = self.sampleCurveDerivativeX(t);
            if (@abs(d) < 1e-6) break;
            t -= x / d;
        }

        // Fall back to bisection if Newton did not converge
        var t0: f32 = 0.0;
        var t1: f32 = 1.0;
        t = x_target;

        var j: usize = 0;
        while (j < 16) : (j += 1) {
            const x = self.sampleCurveX(t);
            if (@abs(x - x_target) < 1e-6) break;
            if (x_target > x) {
                t0 = t;
            } else {
                t1 = t;
            }
            t = (t1 + t0) * 0.5;
        }

        return self.sampleCurveY(t);
    }
};

pub const AnimationDirection = enum {
    Normal,
    Reverse,
    Alternate,
    AlternateReverse,
};

pub const AnimationFillMode = enum {
    None,
    Forwards,
    Backwards,
    Both,
};

pub const AnimationPlayState = enum {
    Running,
    Paused,
};

pub const AnimProperty = struct {
    name: []const u8,
    value: f32, // scalar float (e.g. opacity, width, height, scale, translate)

    pub fn deinit(self: *AnimProperty, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Keyframe = struct {
    offset: f32, // 0.0 to 1.0
    properties: std.ArrayList(AnimProperty),

    pub fn deinit(self: *Keyframe, allocator: std.mem.Allocator) void {
        for (self.properties.items) |*p| {
            p.deinit(allocator);
        }
        self.properties.deinit(allocator);
    }
};

pub const KeyframeAnimation = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    keyframes: std.ArrayList(Keyframe),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !KeyframeAnimation {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .keyframes = .empty,
        };
    }

    pub fn deinit(self: *KeyframeAnimation) void {
        self.allocator.free(self.name);
        for (self.keyframes.items) |*kf| {
            kf.deinit(self.allocator);
        }
        self.keyframes.deinit(self.allocator);
    }

    pub fn addKeyframe(self: *KeyframeAnimation, offset: f32) !*Keyframe {
        try self.keyframes.append(self.allocator, .{
            .offset = offset,
            .properties = .empty,
        });
        return &self.keyframes.items[self.keyframes.items.len - 1];
    }

    /// Parses an @keyframes CSS block e.g.:
    /// @keyframes slideIn { from { opacity: 0; } 50% { opacity: 0.5; } to { opacity: 1; } }
    pub fn parseFromCss(allocator: std.mem.Allocator, css_str: []const u8) !KeyframeAnimation {
        var it = std.mem.tokenizeAny(u8, css_str, " \t\r\n");
        const first = it.next() orelse return error.InvalidKeyframeSyntax;
        if (!std.mem.eql(u8, first, "@keyframes")) return error.ExpectedKeyframesKeyword;

        const name = it.next() orelse return error.ExpectedAnimationName;
        var anim = try KeyframeAnimation.init(allocator, name);
        errdefer anim.deinit();

        const open_brace = std.mem.indexOfScalar(u8, css_str, '{') orelse return error.InvalidKeyframeSyntax;
        const close_brace = std.mem.lastIndexOfScalar(u8, css_str, '}') orelse return error.InvalidKeyframeSyntax;
        if (close_brace <= open_brace) return error.InvalidKeyframeSyntax;

        const body = css_str[open_brace + 1 .. close_brace];
        var cur_pos: usize = 0;

        while (cur_pos < body.len) {
            const next_open = std.mem.indexOfScalarPos(u8, body, cur_pos, '{') orelse break;
            const next_close = std.mem.indexOfScalarPos(u8, body, next_open, '}') orelse break;

            const selector_part = std.mem.trim(u8, body[cur_pos..next_open], " \t\r\n");
            const decl_part = body[next_open + 1 .. next_close];

            var offset: f32 = 0.0;
            if (std.mem.eql(u8, selector_part, "from") or std.mem.eql(u8, selector_part, "0%")) {
                offset = 0.0;
            } else if (std.mem.eql(u8, selector_part, "to") or std.mem.eql(u8, selector_part, "100%")) {
                offset = 1.0;
            } else if (std.mem.endsWith(u8, selector_part, "%")) {
                const pct_str = selector_part[0 .. selector_part.len - 1];
                const pct = std.fmt.parseFloat(f32, pct_str) catch 0.0;
                offset = pct / 100.0;
            }

            const kf = try anim.addKeyframe(offset);

            var decl_it = std.mem.splitScalar(u8, decl_part, ';');
            while (decl_it.next()) |decl| {
                const trimmed = std.mem.trim(u8, decl, " \t\r\n");
                if (trimmed.len == 0) continue;
                if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                    const p_name = std.mem.trim(u8, trimmed[0..colon], " \t\r\n");
                    const p_val_str = std.mem.trim(u8, trimmed[colon + 1 ..], " \t\r\n");
                    const p_val = std.fmt.parseFloat(f32, p_val_str) catch 0.0;

                    try kf.properties.append(allocator, .{
                        .name = try allocator.dupe(u8, p_name),
                        .value = p_val,
                    });
                }
            }

            cur_pos = next_close + 1;
        }

        // Sort keyframes by offset ascending
        const Sorter = struct {
            fn lessThan(_: void, a: Keyframe, b: Keyframe) bool {
                return a.offset < b.offset;
            }
        };
        std.mem.sort(Keyframe, anim.keyframes.items, {}, Sorter.lessThan);

        return anim;
    }
};

pub const AnimationInstance = struct {
    animation: *const KeyframeAnimation,
    duration_ms: f32 = 1000.0,
    delay_ms: f32 = 0.0,
    iteration_count: f32 = 1.0, // 1.0, 2.0, or math.inf(f32) for infinite
    direction: AnimationDirection = .Normal,
    fill_mode: AnimationFillMode = .Forwards,
    play_state: AnimationPlayState = .Running,
    easing: CubicBezier = CubicBezier.ease,

    /// Samples an animated property value at the given elapsed time
    pub fn sampleProperty(self: *const AnimationInstance, prop_name: []const u8, elapsed_ms: f32) ?f32 {
        if (self.animation.keyframes.items.len == 0) return null;

        // 1. Handle delay
        if (elapsed_ms < self.delay_ms) {
            if (self.fill_mode == .Backwards or self.fill_mode == .Both) {
                return self.getPropertyAtKeyframe(0, prop_name);
            }
            return null;
        }

        const active_time = elapsed_ms - self.delay_ms;
        const total_duration = self.duration_ms * self.iteration_count;

        // 2. Handle completion
        if (active_time >= total_duration and !std.math.isInf(self.iteration_count)) {
            if (self.fill_mode == .Forwards or self.fill_mode == .Both) {
                return self.getPropertyAtKeyframe(self.animation.keyframes.items.len - 1, prop_name);
            }
            return null;
        }

        // 3. Compute current iteration and normalized iteration progress (0.0 .. 1.0)
        const iteration_index = @floor(active_time / self.duration_ms);
        const iteration_rem = @rem(active_time, self.duration_ms);
        var norm_prog = iteration_rem / self.duration_ms;

        // 4. Direction handling
        const is_odd = (@as(usize, @intFromFloat(iteration_index)) % 2) == 1;
        switch (self.direction) {
            .Normal => {},
            .Reverse => norm_prog = 1.0 - norm_prog,
            .Alternate => if (is_odd) {
                norm_prog = 1.0 - norm_prog;
            },
            .AlternateReverse => if (!is_odd) {
                norm_prog = 1.0 - norm_prog;
            },
        }

        // 5. Apply easing curve
        const eased_progress = self.easing.solve(norm_prog);

        // 6. Interpolate across keyframes
        return self.interpolateKeyframes(prop_name, eased_progress);
    }

    fn getPropertyAtKeyframe(self: *const AnimationInstance, kf_idx: usize, prop_name: []const u8) ?f32 {
        if (kf_idx >= self.animation.keyframes.items.len) return null;
        const kf = &self.animation.keyframes.items[kf_idx];
        for (kf.properties.items) |p| {
            if (std.mem.eql(u8, p.name, prop_name)) return p.value;
        }
        return null;
    }

    fn interpolateKeyframes(self: *const AnimationInstance, prop_name: []const u8, progress: f32) ?f32 {
        const kfs = self.animation.keyframes.items;
        if (kfs.len == 1) return self.getPropertyAtKeyframe(0, prop_name);

        // Find surrounding keyframes
        var lower_idx: usize = 0;
        var upper_idx: usize = kfs.len - 1;

        for (kfs, 0..) |kf, i| {
            if (kf.offset <= progress) {
                lower_idx = i;
            }
            if (kf.offset >= progress) {
                upper_idx = i;
                break;
            }
        }

        const v0 = self.getPropertyAtKeyframe(lower_idx, prop_name) orelse return null;
        if (lower_idx == upper_idx) return v0;

        const v1 = self.getPropertyAtKeyframe(upper_idx, prop_name) orelse return v0;
        const off0 = kfs[lower_idx].offset;
        const off1 = kfs[upper_idx].offset;

        const range = off1 - off0;
        if (range <= 1e-6) return v1;

        const local_factor = (progress - off0) / range;
        return v0 + (v1 - v0) * local_factor;
    }
};

test "cubic bezier easing curve evaluation and standard curves" {
    // Linear
    const lin = CubicBezier.linear;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), lin.solve(0.0), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), lin.solve(0.5), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), lin.solve(1.0), 1e-4);

    // Ease-in: slower start, faster finish -> y(0.5) < 0.5
    const ease_in = CubicBezier.ease_in;
    const y_in = ease_in.solve(0.5);
    try std.testing.expect(y_in < 0.5);

    // Ease-out: faster start, slower finish -> y(0.5) > 0.5
    const ease_out = CubicBezier.ease_out;
    const y_out = ease_out.solve(0.5);
    try std.testing.expect(y_out > 0.5);
}

test "keyframes parsing from css and animation sampling over time" {
    const allocator = std.testing.allocator;

    const css_code =
        \\@keyframes pulse {
        \\  0% { opacity: 0.2; }
        \\  50% { opacity: 1.0; }
        \\  100% { opacity: 0.2; }
        \\}
    ;

    var anim = try KeyframeAnimation.parseFromCss(allocator, css_code);
    defer anim.deinit();

    try std.testing.expectEqualStrings("pulse", anim.name);
    try std.testing.expectEqual(@as(usize, 3), anim.keyframes.items.len);
    try std.testing.expectEqual(@as(f32, 0.0), anim.keyframes.items[0].offset);
    try std.testing.expectEqual(@as(f32, 0.5), anim.keyframes.items[1].offset);
    try std.testing.expectEqual(@as(f32, 1.0), anim.keyframes.items[2].offset);

    // Create animation instance: 1000ms duration, linear easing for exact interpolation check
    const instance = AnimationInstance{
        .animation = &anim,
        .duration_ms = 1000.0,
        .delay_ms = 0.0,
        .iteration_count = 1.0,
        .direction = .Normal,
        .fill_mode = .Forwards,
        .easing = CubicBezier.linear,
    };

    // At 0ms -> opacity = 0.2
    const v0 = instance.sampleProperty("opacity", 0.0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), v0, 1e-3);

    // At 500ms (50%) -> opacity = 1.0
    const v500 = instance.sampleProperty("opacity", 500.0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), v500, 1e-3);

    // At 250ms (25%) -> halfway between 0.2 and 1.0 -> 0.6
    const v250 = instance.sampleProperty("opacity", 250.0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), v250, 1e-3);

    // At 1000ms (100%) -> opacity = 0.2
    const v1000 = instance.sampleProperty("opacity", 1000.0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), v1000, 1e-3);
}
