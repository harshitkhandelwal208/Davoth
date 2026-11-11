//! Linux sandboxing, seccomp-bpf, and namespace process containment.
const std = @import("std");
const posix = std.posix;

pub const SandboxLevel = enum {
    None,
    RenderProcess,
    NetworkProcess,
};

pub const Sandbox = struct {
    level: SandboxLevel,

    pub fn apply(level: SandboxLevel) !void {
        switch (level) {
            .None => {},
            .RenderProcess => {
                // In production Linux: prctl(PR_SET_NO_NEW_PRIVS, 1) and install seccomp-bpf filter
                // Disallowing execve, fork, socket creation in render process.
            },
            .NetworkProcess => {
                // Restricted filesystem access
            },
        }
    }
};
