const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_includes = [_][]const u8{
        "/usr/include/gtk-4.0",
        "/usr/include/glib-2.0",
        "/usr/lib/glib-2.0/include",
        "/usr/include/pango-1.0",
        "/usr/include/cairo",
        "/usr/include/gdk-pixbuf-2.0",
        "/usr/include/graphene-1.0",
        "/usr/lib/graphene-1.0/include",
        "/usr/include/freetype2",
        "/usr/include/harfbuzz",
    };

    const sys_libs = [_][]const u8{
        "c",
        "sqlite3",
        "ssl",
        "crypto",
        "freetype",
        "harfbuzz",
        "vulkan",
        "gtk-4",
        "gobject-2.0",
        "gio-2.0",
        "glib-2.0",
        "z",
        "cairo",
    };

    const mod = b.addModule("Davoth", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.link_libc = true;
    for (c_includes) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    for (sys_libs) |lib| {
        mod.linkSystemLibrary(lib, .{});
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "Davoth", .module = mod },
        },
    });

    exe_mod.link_libc = true;
    for (c_includes) |inc| {
        exe_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    for (sys_libs) |lib| {
        exe_mod.linkSystemLibrary(lib, .{});
    }

    const exe = b.addExecutable(.{
        .name = "davoth",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run Davoth browser");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all Davoth tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
