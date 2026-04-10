const std = @import("std");
const ops = @import("session_ops.zig");
const page_size = std.heap.page_size_min;

pub const MAGIC: u32 = 0x5A544B31; // "ZTK1"
pub const MAX_ENTRIES: u32 = 256;
pub const HEADER_END: u32 = @sizeOf(Header) + MAX_ENTRIES * @sizeOf(Entry);
const INITIAL_SIZE: u64 = HEADER_END + 64 * 1024;

pub const Header = extern struct {
    magic: u32,
    version: u16,
    count: u16,
    capacity: u32,
    data_offset: u32,
};

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

/// Per-category TTL in nanoseconds, indexed by CommandCategory ordinal.
/// fast_changing=30s, medium=120s, slow_changing=300s, immutable/mutation=never.
const ttl_ns = [_]i128{
    30 * std.time.ns_per_s,
    120 * std.time.ns_per_s,
    300 * std.time.ns_per_s,
    -1,
    -1,
};

pub fn isExpired(entry: *const Entry, now: i128) bool {
    if (entry.category >= ttl_ns.len) return false;
    const ttl = ttl_ns[entry.category];
    if (ttl < 0) return false;
    const ts: i128 = @intCast(entry.timestamp);
    return now - ts > ttl;
}

pub const Session = struct {
    map: []align(page_size) u8,
    fd: std.posix.fd_t,

    pub fn open(dir: []const u8, allocator: std.mem.Allocator) !Session {
        _ = allocator;
        var d = try std.fs.openDirAbsolute(dir, .{});
        defer d.close();
        const file = try d.createFile("ztk-state", .{ .read = true, .truncate = false, .mode = 0o600 });
        const fd = file.handle;
        errdefer std.posix.close(fd);
        const stat = try std.posix.fstat(fd);
        const needs_init = stat.size < @sizeOf(Header);
        if (needs_init) try std.posix.ftruncate(fd, @intCast(INITIAL_SIZE));
        const len: usize = if (needs_init) INITIAL_SIZE else @intCast(stat.size);
        const map = try std.posix.mmap(null, len, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
        errdefer std.posix.munmap(map);
        var s = Session{ .map = map, .fd = fd };
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

    /// Advisory exclusive lock (non-blocking). Returns true if acquired.
    /// Callers should skip session writes on contention and fall back to
    /// stateless mode rather than block.
    pub fn tryLock(self: *Session) bool {
        std.posix.flock(self.fd, std.posix.LOCK.EX | std.posix.LOCK.NB) catch return false;
        return true;
    }

    pub fn unlock(self: *Session) void {
        std.posix.flock(self.fd, std.posix.LOCK.UN) catch {};
    }

    /// Locked insert: acquires the exclusive lock, re-validates the
    /// header (another process may have reinitialized it), then inserts.
    /// Returns error.Busy if the lock cannot be acquired.
    pub fn insert(
        self: *Session,
        cmd_hash: u64,
        out_hash: u64,
        summary: []const u8,
        category: u8,
    ) !void {
        if (!self.tryLock()) return error.Busy;
        defer self.unlock();
        if (!ops.headerValid(self)) ops.resetHeader(self);
        try ops.insert(self, cmd_hash, out_hash, summary, category);
    }

    pub fn close(self: *Session) void {
        std.posix.msync(self.map, std.posix.MSF.SYNC) catch {};
        std.posix.munmap(self.map);
        std.posix.close(self.fd);
    }
};

test {
    _ = @import("session_test.zig");
}
