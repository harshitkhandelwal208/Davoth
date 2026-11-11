//! GTK4 application bootstrap and desktop window integration.
const std = @import("std");
const BrowserShell = @import("shell.zig").BrowserShell;
const c = @import("../common/c.zig");

pub const GtkApp = struct {
    shell: *BrowserShell,

    pub fn init(shell: *BrowserShell) GtkApp {
        return .{ .shell = shell };
    }

    pub fn run(self: *GtkApp, argc: c_int, argv: [*c][*c]u8) c_int {
        const app = c.gtk_application_new("org.davoth.browser", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(app);

        const AppData = struct {
            shell: *BrowserShell,
        };
        var app_data = AppData{ .shell = self.shell };

        const activate = struct {
            fn callback(application: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
                const data: *AppData = @ptrCast(@alignCast(user_data.?));
                const window = c.gtk_application_window_new(application);
                c.gtk_window_set_title(@ptrCast(window), "Davoth Browser");
                c.gtk_window_set_default_size(@ptrCast(window), 1280, 800);

                // Main vertical box
                const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
                c.gtk_window_set_child(@ptrCast(window), vbox);

                // Header / URL bar box
                const header_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
                const url_entry = c.gtk_entry_new();
                c.gtk_widget_set_hexpand(url_entry, 1);
                c.gtk_entry_set_placeholder_text(@ptrCast(url_entry), "Search or enter address");
                c.gtk_box_append(@ptrCast(header_box), url_entry);

                c.gtk_box_append(@ptrCast(vbox), header_box);

                // Initial navigation
                data.shell.navigate("about:home") catch {};

                c.gtk_window_present(@ptrCast(window));
            }
        };

        _ = c.g_signal_connect_data(app, "activate", @ptrCast(&activate.callback), &app_data, null, 0);
        return c.g_application_run(@ptrCast(app), argc, argv);
    }
};
