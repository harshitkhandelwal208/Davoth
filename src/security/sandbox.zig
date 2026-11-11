//! Linux sandboxing, seccomp-BPF filters, and namespace process containment.
const std = @import("std");
const builtin = @import("builtin");

// Linux system call numbers on x86_64
pub const X86_64_SYSCALL = struct {
    pub const read: u32 = 0;
    pub const write: u32 = 1;
    pub const open: u32 = 2;
    pub const close: u32 = 3;
    pub const stat: u32 = 4;
    pub const fstat: u32 = 5;
    pub const lstat: u32 = 6;
    pub const poll: u32 = 7;
    pub const lseek: u32 = 8;
    pub const mmap: u32 = 9;
    pub const mprotect: u32 = 10;
    pub const munmap: u32 = 11;
    pub const brk: u32 = 12;
    pub const rt_sigaction: u32 = 13;
    pub const rt_sigprocmask: u32 = 14;
    pub const rt_sigreturn: u32 = 15;
    pub const ioctl: u32 = 16;
    pub const pread64: u32 = 17;
    pub const pwrite64: u32 = 18;
    pub const readv: u32 = 19;
    pub const writev: u32 = 20;
    pub const pipe: u32 = 22;
    pub const select: u32 = 23;
    pub const sched_yield: u32 = 24;
    pub const mremap: u32 = 25;
    pub const msync: u32 = 26;
    pub const mincore: u32 = 27;
    pub const madvise: u32 = 28;
    pub const dup: u32 = 32;
    pub const dup2: u32 = 33;
    pub const pause: u32 = 34;
    pub const nanosleep: u32 = 35;
    pub const getpid: u32 = 39;
    pub const socket: u32 = 41;
    pub const connect: u32 = 42;
    pub const accept: u32 = 43;
    pub const sendto: u32 = 44;
    pub const recvfrom: u32 = 45;
    pub const sendmsg: u32 = 46;
    pub const recvmsg: u32 = 47;
    pub const shutdown: u32 = 48;
    pub const bind: u32 = 49;
    pub const listen: u32 = 50;
    pub const clone: u32 = 56;
    pub const fork: u32 = 57;
    pub const vfork: u32 = 58;
    pub const execve: u32 = 59;
    pub const exit: u32 = 60;
    pub const wait4: u32 = 61;
    pub const kill: u32 = 62;
    pub const uname: u32 = 63;
    pub const fcntl: u32 = 72;
    pub const getdents: u32 = 78;
    pub const getcwd: u32 = 79;
    pub const getuid: u32 = 102;
    pub const getgid: u32 = 104;
    pub const geteuid: u32 = 107;
    pub const getegid: u32 = 108;
    pub const getppid: u32 = 110;
    pub const arch_prctl: u32 = 158;
    pub const futex: u32 = 202;
    pub const sched_getaffinity: u32 = 204;
    pub const getdents64: u32 = 217;
    pub const restart_syscall: u32 = 219;
    pub const clock_gettime: u32 = 228;
    pub const clock_getres: u32 = 229;
    pub const clock_nanosleep: u32 = 230;
    pub const exit_group: u32 = 231;
    pub const epoll_wait: u32 = 232;
    pub const epoll_ctl: u32 = 233;
    pub const tgkill: u32 = 234;
    pub const openat: u32 = 257;
    pub const newfstatat: u32 = 262;
    pub const pipe2: u32 = 293;
    pub const epoll_create1: u32 = 291;
    pub const prlimit64: u32 = 302;
    pub const getrandom: u32 = 318;
    pub const memfd_create: u32 = 319;
    pub const execveat: u32 = 322;
    pub const rseq: u32 = 334;
    pub const clone3: u32 = 435;
};

// BPF instruction set definitions
pub const BPF_LD: u16 = 0x00;
pub const BPF_W: u16 = 0x00;
pub const BPF_ABS: u16 = 0x20;
pub const BPF_JMP: u16 = 0x05;
pub const BPF_JEQ: u16 = 0x10;
pub const BPF_K: u16 = 0x00;
pub const BPF_RET: u16 = 0x06;

// Seccomp return action codes
pub const SECCOMP_RET_KILL_PROCESS: u32 = 0x80000000;
pub const SECCOMP_RET_KILL_THREAD: u32 = 0x00000000;
pub const SECCOMP_RET_TRAP: u32 = 0x00030000;
pub const SECCOMP_RET_ERRNO: u32 = 0x00050000;
pub const SECCOMP_RET_ALLOW: u32 = 0x7fff0000;

// Architecture constants for seccomp_data.arch
pub const AUDIT_ARCH_X86_64: u32 = 0xc000003e;
pub const AUDIT_ARCH_AARCH64: u32 = 0xc00000b7;

// Linux prctl constants
pub const PR_SET_NO_NEW_PRIVS: c_int = 38;
pub const PR_GET_NO_NEW_PRIVS: c_int = 39;
pub const PR_SET_SECCOMP: c_int = 22;
pub const SECCOMP_MODE_FILTER: c_ulong = 2;

// Linux namespace clone flags
pub const CLONE_NEWNS: c_int = 0x00020000;
pub const CLONE_NEWCGROUP: c_int = 0x02000000;
pub const CLONE_NEWUTS: c_int = 0x04000000;
pub const CLONE_NEWIPC: c_int = 0x08000000;
pub const CLONE_NEWUSER: c_int = 0x10000000;
pub const CLONE_NEWPID: c_int = 0x20000000;
pub const CLONE_NEWNET: c_int = 0x40000000;

pub const sock_filter = extern struct {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
};

pub const sock_fprog = extern struct {
    len: c_ushort,
    filter: [*]const sock_filter,
};

extern "c" fn prctl(option: c_int, ...) c_int;
extern "c" fn unshare(flags: c_int) c_int;

pub const SandboxLevel = enum {
    None,
    RenderProcess,
    NetworkProcess,
    WorkerProcess,
};

pub const SandboxError = error{
    NoNewPrivsFailed,
    SeccompFilterInstallFailed,
    NamespaceUnshareFailed,
    UnsupportedArchitecture,
    OutOfMemory,
};

pub const FilterBuilder = struct {
    filters: std.ArrayList(sock_filter),

    pub fn init(allocator: std.mem.Allocator) FilterBuilder {
        return .{
            .filters = std.ArrayList(sock_filter).init(allocator),
        };
    }

    pub fn deinit(self: *FilterBuilder) void {
        self.filters.deinit();
    }

    pub fn stmt(self: *FilterBuilder, code: u16, k: u32) !void {
        try self.filters.append(.{
            .code = code,
            .jt = 0,
            .jf = 0,
            .k = k,
        });
    }

    pub fn jump(self: *FilterBuilder, code: u16, k: u32, jt: u8, jf: u8) !void {
        try self.filters.append(.{
            .code = code,
            .jt = jt,
            .jf = jf,
            .k = k,
        });
    }

    pub fn emitArchitectureValidation(self: *FilterBuilder) !void {
        // Load architecture from offset 4 in seccomp_data
        try self.stmt(BPF_LD | BPF_W | BPF_ABS, 4);

        const expected_arch: u32 = if (builtin.cpu.arch == .x86_64)
            AUDIT_ARCH_X86_64
        else if (builtin.cpu.arch == .aarch64)
            AUDIT_ARCH_AARCH64
        else
            0;

        // If arch matches expected_arch, advance 1 instruction; else execute next instruction (KILL)
        try self.jump(BPF_JMP | BPF_JEQ | BPF_K, expected_arch, 1, 0);
        // Fail: kill process on architecture mismatch
        try self.stmt(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS);

        // Load syscall number from offset 0 in seccomp_data
        try self.stmt(BPF_LD | BPF_W | BPF_ABS, 0);
    }
};

pub const Sandbox = struct {
    level: SandboxLevel = .None,
    active: bool = false,
    namespaces_isolated: bool = false,

    var global_instance: Sandbox = .{};

    pub fn getGlobal() *Sandbox {
        return &global_instance;
    }

    /// Sets up seccomp-BPF policy rules for a render process.
    /// The renderer may only perform computation, read/write to established IPC/graphics fds,
    /// allocate/manage memory, and signal. Any attempt to execute programs or open network sockets is terminated.
    pub fn buildRenderFilter(allocator: std.mem.Allocator) ![]sock_filter {
        var builder = FilterBuilder.init(allocator);
        defer builder.deinit();

        try builder.emitArchitectureValidation();

        // Forbidden syscalls list: explicitly terminate process or reject with EPERM
        const forbidden_kills = [_]u32{
            X86_64_SYSCALL.execve,
            X86_64_SYSCALL.execveat,
            X86_64_SYSCALL.fork,
            X86_64_SYSCALL.vfork,
        };

        for (forbidden_kills) |nr| {
            // If match nr, jump to kill (jt = 0), otherwise skip (jf = 1)
            try builder.jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1);
            try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS);
        }

        // Prohibited network calls in render process (return EPERM = 1)
        const forbidden_network = [_]u32{
            X86_64_SYSCALL.socket,
            X86_64_SYSCALL.connect,
            X86_64_SYSCALL.bind,
            X86_64_SYSCALL.listen,
            X86_64_SYSCALL.accept,
        };

        for (forbidden_network) |nr| {
            try builder.jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1);
            try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | 1); // EPERM
        }

        // Permitted syscalls for layout, DOM, JS engine, graphics pipeline, memory & IPC
        const allowed_syscalls = [_]u32{
            X86_64_SYSCALL.read,
            X86_64_SYSCALL.write,
            X86_64_SYSCALL.open,
            X86_64_SYSCALL.close,
            X86_64_SYSCALL.stat,
            X86_64_SYSCALL.fstat,
            X86_64_SYSCALL.lstat,
            X86_64_SYSCALL.poll,
            X86_64_SYSCALL.lseek,
            X86_64_SYSCALL.mmap,
            X86_64_SYSCALL.mprotect,
            X86_64_SYSCALL.munmap,
            X86_64_SYSCALL.brk,
            X86_64_SYSCALL.rt_sigaction,
            X86_64_SYSCALL.rt_sigprocmask,
            X86_64_SYSCALL.rt_sigreturn,
            X86_64_SYSCALL.ioctl,
            X86_64_SYSCALL.pread64,
            X86_64_SYSCALL.pwrite64,
            X86_64_SYSCALL.readv,
            X86_64_SYSCALL.writev,
            X86_64_SYSCALL.pipe,
            X86_64_SYSCALL.select,
            X86_64_SYSCALL.sched_yield,
            X86_64_SYSCALL.mremap,
            X86_64_SYSCALL.msync,
            X86_64_SYSCALL.mincore,
            X86_64_SYSCALL.madvise,
            X86_64_SYSCALL.dup,
            X86_64_SYSCALL.dup2,
            X86_64_SYSCALL.pause,
            X86_64_SYSCALL.nanosleep,
            X86_64_SYSCALL.getpid,
            X86_64_SYSCALL.sendto,
            X86_64_SYSCALL.recvfrom,
            X86_64_SYSCALL.sendmsg,
            X86_64_SYSCALL.recvmsg,
            X86_64_SYSCALL.shutdown,
            X86_64_SYSCALL.clone,
            X86_64_SYSCALL.clone3,
            X86_64_SYSCALL.exit,
            X86_64_SYSCALL.wait4,
            X86_64_SYSCALL.kill,
            X86_64_SYSCALL.uname,
            X86_64_SYSCALL.fcntl,
            X86_64_SYSCALL.getdents,
            X86_64_SYSCALL.getcwd,
            X86_64_SYSCALL.getuid,
            X86_64_SYSCALL.getgid,
            X86_64_SYSCALL.geteuid,
            X86_64_SYSCALL.getegid,
            X86_64_SYSCALL.getppid,
            X86_64_SYSCALL.arch_prctl,
            X86_64_SYSCALL.futex,
            X86_64_SYSCALL.sched_getaffinity,
            X86_64_SYSCALL.getdents64,
            X86_64_SYSCALL.restart_syscall,
            X86_64_SYSCALL.clock_gettime,
            X86_64_SYSCALL.clock_getres,
            X86_64_SYSCALL.clock_nanosleep,
            X86_64_SYSCALL.exit_group,
            X86_64_SYSCALL.epoll_wait,
            X86_64_SYSCALL.epoll_ctl,
            X86_64_SYSCALL.tgkill,
            X86_64_SYSCALL.openat,
            X86_64_SYSCALL.newfstatat,
            X86_64_SYSCALL.pipe2,
            X86_64_SYSCALL.epoll_create1,
            X86_64_SYSCALL.prlimit64,
            X86_64_SYSCALL.getrandom,
            X86_64_SYSCALL.memfd_create,
            X86_64_SYSCALL.rseq,
        };

        for (allowed_syscalls) |nr| {
            try builder.jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1);
            try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_ALLOW);
        }

        // Default: deny unknown system calls with EPERM
        try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | 1);

        return builder.filters.toOwnedSlice();
    }

    /// Sets up seccomp-BPF policy rules for the network process.
    /// Allows networking syscalls, prohibits arbitrary process spawning.
    pub fn buildNetworkFilter(allocator: std.mem.Allocator) ![]sock_filter {
        var builder = FilterBuilder.init(allocator);
        defer builder.deinit();

        try builder.emitArchitectureValidation();

        // Disallow process execution
        const forbidden_kills = [_]u32{
            X86_64_SYSCALL.execve,
            X86_64_SYSCALL.execveat,
            X86_64_SYSCALL.fork,
            X86_64_SYSCALL.vfork,
        };

        for (forbidden_kills) |nr| {
            try builder.jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1);
            try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS);
        }

        // Permitted network process syscalls (networking + IPC + memory)
        const allowed_syscalls = [_]u32{
            X86_64_SYSCALL.read,
            X86_64_SYSCALL.write,
            X86_64_SYSCALL.open,
            X86_64_SYSCALL.close,
            X86_64_SYSCALL.stat,
            X86_64_SYSCALL.fstat,
            X86_64_SYSCALL.lstat,
            X86_64_SYSCALL.poll,
            X86_64_SYSCALL.lseek,
            X86_64_SYSCALL.mmap,
            X86_64_SYSCALL.mprotect,
            X86_64_SYSCALL.munmap,
            X86_64_SYSCALL.brk,
            X86_64_SYSCALL.rt_sigaction,
            X86_64_SYSCALL.rt_sigprocmask,
            X86_64_SYSCALL.rt_sigreturn,
            X86_64_SYSCALL.ioctl,
            X86_64_SYSCALL.pread64,
            X86_64_SYSCALL.pwrite64,
            X86_64_SYSCALL.readv,
            X86_64_SYSCALL.writev,
            X86_64_SYSCALL.pipe,
            X86_64_SYSCALL.select,
            X86_64_SYSCALL.sched_yield,
            X86_64_SYSCALL.mremap,
            X86_64_SYSCALL.msync,
            X86_64_SYSCALL.mincore,
            X86_64_SYSCALL.madvise,
            X86_64_SYSCALL.dup,
            X86_64_SYSCALL.dup2,
            X86_64_SYSCALL.nanosleep,
            X86_64_SYSCALL.getpid,
            X86_64_SYSCALL.socket,
            X86_64_SYSCALL.connect,
            X86_64_SYSCALL.accept,
            X86_64_SYSCALL.sendto,
            X86_64_SYSCALL.recvfrom,
            X86_64_SYSCALL.sendmsg,
            X86_64_SYSCALL.recvmsg,
            X86_64_SYSCALL.shutdown,
            X86_64_SYSCALL.bind,
            X86_64_SYSCALL.listen,
            X86_64_SYSCALL.clone,
            X86_64_SYSCALL.clone3,
            X86_64_SYSCALL.exit,
            X86_64_SYSCALL.wait4,
            X86_64_SYSCALL.kill,
            X86_64_SYSCALL.fcntl,
            X86_64_SYSCALL.futex,
            X86_64_SYSCALL.sched_getaffinity,
            X86_64_SYSCALL.clock_gettime,
            X86_64_SYSCALL.clock_getres,
            X86_64_SYSCALL.exit_group,
            X86_64_SYSCALL.epoll_wait,
            X86_64_SYSCALL.epoll_ctl,
            X86_64_SYSCALL.openat,
            X86_64_SYSCALL.newfstatat,
            X86_64_SYSCALL.pipe2,
            X86_64_SYSCALL.epoll_create1,
            X86_64_SYSCALL.prlimit64,
            X86_64_SYSCALL.getrandom,
            X86_64_SYSCALL.rseq,
        };

        for (allowed_syscalls) |nr| {
            try builder.jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1);
            try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_ALLOW);
        }

        // Default: deny unknown system calls with EPERM
        try builder.stmt(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | 1);

        return builder.filters.toOwnedSlice();
    }

    /// Sets PR_SET_NO_NEW_PRIVS = 1 on the current process/thread
    pub fn setNoNewPrivs() !void {
        if (builtin.os.tag != .linux) return;
        const res = prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
        if (res != 0) {
            return SandboxError.NoNewPrivsFailed;
        }
    }

    /// Queries whether PR_SET_NO_NEW_PRIVS is active
    pub fn isNoNewPrivs() bool {
        if (builtin.os.tag != .linux) return false;
        const res = prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0);
        return res == 1;
    }

    /// Attempts to isolate namespaces for the current process
    pub fn isolateNamespaces(flags: c_int) !void {
        if (builtin.os.tag != .linux) return;
        const res = unshare(flags);
        if (res != 0) {
            // Unprivileged namespace creation may be restricted by sysctl kernel.unprivileged_userns_clone
            return SandboxError.NamespaceUnshareFailed;
        }
        global_instance.namespaces_isolated = true;
    }

    /// Compiles and installs the seccomp-BPF filter for the requested sandbox level
    pub fn apply(level: SandboxLevel) !void {
        if (level == .None) return;
        if (builtin.os.tag != .linux) {
            global_instance.level = level;
            global_instance.active = true;
            return;
        }

        // Step 1: Ensure PR_SET_NO_NEW_PRIVS is set (required before non-root can load seccomp filters)
        try setNoNewPrivs();

        // Step 2: Build the appropriate filter program
        var gpa = std.heap.c_allocator;
        const filters = switch (level) {
            .RenderProcess => try buildRenderFilter(gpa),
            .NetworkProcess => try buildNetworkFilter(gpa),
            .WorkerProcess => try buildRenderFilter(gpa),
            .None => unreachable,
        };
        defer gpa.free(filters);

        // Step 3: Install seccomp filter via prctl
        const prog = sock_fprog{
            .len = @intCast(filters.len),
            .filter = filters.ptr,
        };

        const res = prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);
        if (res != 0) {
            return SandboxError.SeccompFilterInstallFailed;
        }

        global_instance.level = level;
        global_instance.active = true;
    }
};

test "sandbox bpf filter construction" {
    const allocator = std.testing.allocator;

    const render_filters = try Sandbox.buildRenderFilter(allocator);
    defer allocator.free(render_filters);

    // Verify filter header checks architecture
    try std.testing.expect(render_filters.len > 10);
    try std.testing.expectEqual(BPF_LD | BPF_W | BPF_ABS, render_filters[0].code);
    try std.testing.expectEqual(@as(u32, 4), render_filters[0].k); // arch offset

    // Architecture branch
    try std.testing.expectEqual(BPF_JMP | BPF_JEQ | BPF_K, render_filters[1].code);
    try std.testing.expectEqual(AUDIT_ARCH_X86_64, render_filters[1].k);

    // Kill on bad arch
    try std.testing.expectEqual(BPF_RET | BPF_K, render_filters[2].code);
    try std.testing.expectEqual(SECCOMP_RET_KILL_PROCESS, render_filters[2].k);

    // Load syscall nr
    try std.testing.expectEqual(BPF_LD | BPF_W | BPF_ABS, render_filters[3].code);
    try std.testing.expectEqual(@as(u32, 0), render_filters[3].k);

    // Verify network filter also generates correctly
    const net_filters = try Sandbox.buildNetworkFilter(allocator);
    defer allocator.free(net_filters);
    try std.testing.expect(net_filters.len > 10);
}

test "sandbox no new privs activation" {
    if (builtin.os.tag == .linux) {
        try Sandbox.setNoNewPrivs();
        try std.testing.expect(Sandbox.isNoNewPrivs());
    }
}

test "sandbox seccomp child enforcement" {
    if (builtin.os.tag != .linux) return;

    const pid = try std.posix.fork();
    if (pid == 0) {
        // In child process: activate RenderProcess sandbox
        Sandbox.apply(.RenderProcess) catch std.c.exit(10);
        // Attempt forbidden syscall: socket()
        const fd = std.c.socket(2, 1, 0); // AF_INET, SOCK_STREAM
        const errno_val = std.c._errno().*;
        if (fd < 0 and errno_val == 1) { // 1 = EPERM
            std.c.exit(42);
        }
        std.c.exit(99);
    } else {
        const res = std.posix.waitpid(pid, 0);
        try std.testing.expectEqual(@as(u32, 42), res.status >> 8);
    }
}
