//! Multiprocess IPC: Message serialization, channel abstraction, and protocol messages.
const std = @import("std");
const posix = std.posix;

pub const ProcessType = enum(u8) {
    UI,
    Render,
    Network,
    GPU,
    Extension,
};

pub const MessageType = enum(u16) {
    Heartbeat = 1,
    Navigate = 2,
    NavigateComplete = 3,
    RenderFrame = 4,
    InputEvent = 5,
    DOMTitleChanged = 6,
    DOMFaviconChanged = 7,
    StorageGet = 8,
    StorageSet = 9,
    StorageResponse = 10,
    ExtensionMessage = 11,
    MemoryPressure = 12,
    TabFrozen = 13,
    TabThawed = 14,
    Crash = 15,
};

pub const Message = struct {
    msg_type: MessageType,
    request_id: u32 = 0,
    payload: []const u8 = "",

    pub fn serialize(self: Message, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        // Header: [type: u16] [req_id: u32] [len: u32]
        var header: [10]u8 = undefined;
        std.mem.writeInt(u16, header[0..2], @intFromEnum(self.msg_type), .little);
        std.mem.writeInt(u32, header[2..6], self.request_id, .little);
        std.mem.writeInt(u32, header[6..10], @intCast(self.payload.len), .little);

        try buf.appendSlice(allocator, &header);
        try buf.appendSlice(allocator, self.payload);
        return buf.toOwnedSlice(allocator);
    }

    pub fn deserialize(bytes: []const u8) !Message {
        if (bytes.len < 10) return error.BufferTooSmall;
        const msg_type_raw = std.mem.readInt(u16, bytes[0..2], .little);
        const req_id = std.mem.readInt(u32, bytes[2..6], .little);
        const payload_len = std.mem.readInt(u32, bytes[6..10], .little);

        if (bytes.len < 10 + payload_len) return error.IncompletePayload;
        const msg_type: MessageType = @enumFromInt(msg_type_raw);
        return Message{
            .msg_type = msg_type,
            .request_id = req_id,
            .payload = bytes[10 .. 10 + payload_len],
        };
    }
};

pub const Channel = struct {
    read_fd: c_int,
    write_fd: c_int,
    allocator: std.mem.Allocator,

    pub fn createPair(allocator: std.mem.Allocator) !struct { parent: Channel, child: Channel } {
        var p1: [2]c_int = undefined;
        var p2: [2]c_int = undefined;
        if (std.c.pipe(&p1) != 0) return error.PipeFailed;
        if (std.c.pipe(&p2) != 0) {
            _ = std.c.close(p1[0]);
            _ = std.c.close(p1[1]);
            return error.PipeFailed;
        }

        return .{
            .parent = .{
                .read_fd = p1[0],
                .write_fd = p2[1],
                .allocator = allocator,
            },
            .child = .{
                .read_fd = p2[0],
                .write_fd = p1[1],
                .allocator = allocator,
            },
        };
    }

    pub fn deinit(self: *Channel) void {
        _ = std.c.close(self.read_fd);
        _ = std.c.close(self.write_fd);
    }

    pub fn send(self: *Channel, msg: Message) !void {
        const serialized = try msg.serialize(self.allocator);
        defer self.allocator.free(serialized);

        var sent: usize = 0;
        while (sent < serialized.len) {
            const n = std.c.write(self.write_fd, serialized[sent..].ptr, serialized[sent..].len);
            if (n <= 0) return error.BrokenPipe;
            sent += @intCast(n);
        }
    }

    pub fn receive(self: *Channel, buffer: []u8) !Message {
        var header_buf: [10]u8 = undefined;
        var read_bytes: usize = 0;
        while (read_bytes < 10) {
            const n = std.c.read(self.read_fd, header_buf[read_bytes..].ptr, 10 - read_bytes);
            if (n <= 0) return error.EndOfStream;
            read_bytes += @intCast(n);
        }

        const msg_type_raw = std.mem.readInt(u16, header_buf[0..2], .little);
        const req_id = std.mem.readInt(u32, header_buf[2..6], .little);
        const payload_len = std.mem.readInt(u32, header_buf[6..10], .little);

        if (payload_len > buffer.len) return error.BufferOverflow;

        var payload_read: usize = 0;
        while (payload_read < payload_len) {
            const n = std.c.read(self.read_fd, buffer[payload_read..payload_len].ptr, payload_len - payload_read);
            if (n <= 0) return error.EndOfStream;
            payload_read += @intCast(n);
        }

        const msg_type: MessageType = @enumFromInt(msg_type_raw);
        return Message{
            .msg_type = msg_type,
            .request_id = req_id,
            .payload = buffer[0..payload_len],
        };
    }
};

test "ipc message serialization" {
    const allocator = std.testing.allocator;
    const msg = Message{
        .msg_type = .Navigate,
        .request_id = 42,
        .payload = "https://davoth.org",
    };

    const bytes = try msg.serialize(allocator);
    defer allocator.free(bytes);

    const parsed = try Message.deserialize(bytes);
    try std.testing.expectEqual(MessageType.Navigate, parsed.msg_type);
    try std.testing.expectEqual(@as(u32, 42), parsed.request_id);
    try std.testing.expectEqualStrings("https://davoth.org", parsed.payload);
}
