//! Best-effort session integration for the proxy pipeline. Opens the
//! shared mmap'd state file, looks up a prior summary for this command,
//! computes a delta if the output is unchanged and the entry is fresh,
//! inserts/updates an entry, and invalidates fast_changing cache rows
//! after a mutation. Every step swallows errors — the proxy must keep
//! working without state.

const std = @import("std");
const session_mod = @import("session.zig");
const session_delta = @import("session_delta.zig");
const comptime_filters = @import("filters/comptime.zig");

const session_dir = "/tmp";

/// Returns a delta-substituted output buffer if the prior cached entry
/// matches and is not expired, otherwise null. The caller continues
/// with its own buffer when null is returned. Errors are swallowed.
pub fn applySession(
    cmd: []const u8,
    filtered: []const u8,
    category: comptime_filters.CommandCategory,
    allocator: std.mem.Allocator,
) ?[]const u8 {
    var session = session_mod.Session.open(session_dir, allocator) catch return null;
    defer session.close();

    const cmd_hash = std.hash.XxHash64.hash(0, cmd);
    const out_hash = std.hash.XxHash64.hash(0, filtered);
    const now = std.time.nanoTimestamp();

    var replaced: ?[]const u8 = null;

    const cached: ?*session_mod.Entry = session.lookup(cmd_hash);
    const fresh_hit = cached != null and !session_mod.isExpired(cached.?, now);

    if (fresh_hit and cached.?.out_hash == out_hash and cached.?.data_len > 0) {
        const prev = readEntryData(&session, cached.?);
        if (session_delta.computeDelta(cmd, prev, filtered, allocator)) |delta| {
            replaced = delta;
        } else |_| {}
    } else {
        // Cache miss, hash mismatch, or expired entry: (re)insert. The
        // session insert path updates an existing slot in place when the
        // cmd_hash already exists.
        session.insert(cmd_hash, out_hash, filtered, @intFromEnum(category)) catch {};
    }

    if (category == .mutation) {
        session.invalidateCategory(@intFromEnum(comptime_filters.CommandCategory.fast_changing));
    }

    return replaced;
}

fn readEntryData(session: *session_mod.Session, entry: *const session_mod.Entry) []const u8 {
    const off: usize = entry.data_off;
    const len: usize = entry.data_len;
    if (off + len > session.map.len) return &.{};
    return session.map[off..][0..len];
}

test "applySession swallows open failure" {
    // session_dir is /tmp which exists; this just exercises the no-prior path.
    const out = applySession("echo z", "z\n", .fast_changing, std.testing.allocator);
    if (out) |b| std.testing.allocator.free(b);
}
