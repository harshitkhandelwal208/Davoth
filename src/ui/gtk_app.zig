//! GTK4 application bootstrap, drawing area compositor presentation, and URL bar interaction.
const std = @import("std");
const BrowserShell = @import("shell.zig").BrowserShell;
const c = @import("../common/c.zig");

pub const AppContext = struct {
    shell: *BrowserShell,
    drawing_area: ?*c.GtkWidget = null,
    url_entry: ?*c.GtkWidget = null,
};

pub const GtkApp = struct {
    shell: *BrowserShell,
    app_ctx: AppContext,

    pub fn init(shell: *BrowserShell) GtkApp {
        return .{
            .shell = shell,
            .app_ctx = .{ .shell = shell },
        };
    }

    pub fn run(self: *GtkApp, argc: c_int, argv: [*c][*c]u8) c_int {
        const app = c.gtk_application_new("org.davoth.browser", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(app);

        const activate = struct {
            fn callback(application: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
                const ctx: *AppContext = @ptrCast(@alignCast(user_data.?));
                const window = c.gtk_application_window_new(application);
                c.gtk_window_set_title(@ptrCast(window), "Davoth Browser");
                c.gtk_window_set_default_size(@ptrCast(window), 1280, 800);

                // Main vertical box
                const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
                c.gtk_window_set_child(@ptrCast(window), vbox);

                // Header / URL bar box
                const header_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
                const url_entry = c.gtk_entry_new();
                ctx.url_entry = url_entry;
                c.gtk_widget_set_hexpand(url_entry, 1);
                c.gtk_entry_set_placeholder_text(@ptrCast(url_entry), "Search or enter address (e.g., https://, file://, about:home)");
                c.gtk_box_append(@ptrCast(header_box), url_entry);

                c.gtk_box_append(@ptrCast(vbox), header_box);

                // Drawing area for rendered web content
                const drawing_area = c.gtk_drawing_area_new();
                ctx.drawing_area = drawing_area;
                c.gtk_widget_set_hexpand(drawing_area, 1);
                c.gtk_widget_set_vexpand(drawing_area, 1);

                // Draw callback connecting SoftwareRasterizer pixel buffer to Cairo surface
                const draw_cb = struct {
                    fn draw(_: ?*c.GtkWidget, cr: ?*c.cairo_t, width: c_int, height: c_int, udata: ?*anyopaque) callconv(.c) void {
                        _ = width;
                        _ = height;
                        const dctx: *AppContext = @ptrCast(@alignCast(udata.?));
                        const r = &dctx.shell.rasterizer;
                        if (r.pixels.len == 0) return;

                        const stride = @as(c_int, @intCast(r.width * 4));
                        const surface = c.cairo_image_surface_create_for_data(
                            @ptrCast(r.pixels.ptr),
                            c.CAIRO_FORMAT_ARGB32,
                            @intCast(r.width),
                            @intCast(r.height),
                            stride,
                        );
                        if (surface) |surf| {
                            defer c.cairo_surface_destroy(surf);
                            c.cairo_set_source_surface(cr, surf, 0.0, 0.0);
                            c.cairo_paint(cr);
                        }
                    }
                };

                c.gtk_drawing_area_set_draw_func(drawing_area, @ptrCast(&draw_cb.draw), ctx, null);
                c.gtk_box_append(@ptrCast(vbox), drawing_area);

                // URL entry "activate" signal (user pressed Enter)
                const entry_activate_cb = struct {
                    fn onActivate(entry: ?*anyopaque, udata: ?*anyopaque) callconv(.c) void {
                        const actx: *AppContext = @ptrCast(@alignCast(udata.?));
                        const text_ptr = c.gtk_editable_get_text(entry);
                        const text = std.mem.span(text_ptr);
                        if (text.len > 0) {
                            actx.shell.navigate(text) catch |err| {
                                std.debug.print("Navigation error for {s}: {any}\n", .{ text, err });
                            };
                            if (actx.drawing_area) |da| {
                                c.gtk_widget_queue_draw(da);
                            }
                        }
                    }
                };

                _ = c.g_signal_connect_data(url_entry, "activate", @ptrCast(&entry_activate_cb.onActivate), ctx, null, 0);

                // Key controller for Vim modal navigation
                const key_controller = c.gtk_event_controller_key_new();
                if (key_controller) |kc| {
                    const key_pressed_cb = struct {
                        fn onKeyPressed(_: ?*anyopaque, keyval: c_uint, _: c_uint, _: c_uint, udata: ?*anyopaque) callconv(.c) c_int {
                            const kctx: *AppContext = @ptrCast(@alignCast(udata.?));
                            if (keyval < 128) {
                                const key: u8 = @intCast(keyval);
                                _ = kctx.shell.handleVimKey(key) catch {};
                                if (kctx.drawing_area) |da| {
                                    c.gtk_widget_queue_draw(da);
                                }
                            }
                            return 0;
                        }
                    };
                    _ = c.g_signal_connect_data(kc, "key-pressed", @ptrCast(&key_pressed_cb.onKeyPressed), ctx, null, 0);
                    c.gtk_widget_add_controller(@ptrCast(window), kc);
                }

                // Initial navigation to about:home
                ctx.shell.navigate("about:home") catch {};

                c.gtk_window_present(@ptrCast(window));
            }
        };

        _ = c.g_signal_connect_data(app, "activate", @ptrCast(&activate.callback), &self.app_ctx, null, 0);
        return c.g_application_run(@ptrCast(app), argc, argv);
    }
};
