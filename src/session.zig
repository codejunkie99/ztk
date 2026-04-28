const std = @import("std");
const ops = @import("session_ops.zig");
const map_io = @import("session_map.zig");
const lock_io = @import("session_lock.zig");
const compat = @import("compat.zig");
const page_size = std.heap.page_size_min;
pub const MAGIC: u32 = 0x5A544B31;
pub const MAX_ENTRIES: u32 = 256;
pub const HEADER_END: u32 = @sizeOf(Header) + MAX_ENTRIES * @sizeOf(Entry);
const INITIAL_SIZE: u64 = HEADER_END + 64 * 1024;

pub const Header = extern struct { magic: u32, version: u16, count: u16, capacity: u32, data_offset: u32 };
pub const Entry = extern struct {
    cmd_hash: u64,
    out_hash: u64,
    timestamp: u64,
    data_off: u32,
    data_len: u32,
    original_len: u32,
    hits: u16,
    flags: u16,
    category: u8,
    _pad: [7]u8 = .{0} ** 7,
};
comptime {
    std.debug.assert(@sizeOf(Header) == 16);
    std.debug.assert(@sizeOf(Entry) == 48);
}
const ttl_ns = [_]i128{ 30 * std.time.ns_per_s, 120 * std.time.ns_per_s, 300 * std.time.ns_per_s, -1, -1 };
pub fn isExpired(entry: *const Entry, now: i128) bool {
    if (entry.category >= ttl_ns.len) return false;
    const ttl = ttl_ns[entry.category];
    return ttl >= 0 and now - @as(i128, @intCast(entry.timestamp)) > ttl;
}

pub const Session = struct {
    map: []align(page_size) u8,
    file: compat.File,
    mapping: ?std.os.windows.HANDLE = null,

    pub fn open(dir: []const u8, allocator: std.mem.Allocator) !Session {
        _ = allocator;
        const d = try compat.openDirAbsolute(dir, .{});
        defer compat.closeDir(d);
        const file = try d.createFile(compat.io(), "ztk-state", .{
            .read = true,
            .truncate = false,
            .permissions = compat.permissionsFromMode(0o600),
        });
        errdefer compat.closeFile(file);
        const stat = try compat.statFile(file);
        const needs_init = stat.size < @sizeOf(Header);
        const mapping = try map_io.open(file, if (needs_init) @intCast(INITIAL_SIZE) else @intCast(stat.size), needs_init);
        var s = Session{ .map = mapping.map, .file = file, .mapping = mapping.handle };
        if (needs_init or !ops.headerValid(&s)) ops.resetHeader(&s);
        return s;
    }

    pub fn header(self: *Session) *Header {
        return @ptrCast(@alignCast(self.map.ptr));
    }
    pub fn entrySlice(self: *Session) [*]Entry {
        return @ptrCast(@alignCast(self.map.ptr + @sizeOf(Header)));
    }
    pub const lookup = ops.lookup;
    pub const invalidateCategory = ops.invalidateCategory;
    pub fn tryLock(self: *Session) bool {
        return lock_io.tryExclusive(self.file);
    }
    pub fn unlock(self: *Session) void {
        lock_io.unlock(self.file);
    }

    pub fn insert(self: *Session, cmd_hash: u64, out_hash: u64, summary: []const u8, category: u8) !void {
        if (!self.tryLock()) return error.Busy;
        defer self.unlock();
        if (!ops.headerValid(self)) ops.resetHeader(self);
        try ops.insert(self, cmd_hash, out_hash, summary, category);
    }

    pub fn close(self: *Session) void {
        map_io.close(.{ .map = self.map, .handle = self.mapping });
        compat.closeFile(self.file);
    }
};

test {
    _ = @import("session_test.zig");
}
