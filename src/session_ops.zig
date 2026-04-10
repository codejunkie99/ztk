//! Operations on an open `Session`: header validation, lookup, insert
//! (with in-place update for repeat commands), and category invalidation.
//! Split out from session.zig to keep both files under the line cap.

const std = @import("std");
const session = @import("session.zig");

pub fn headerValid(self: *session.Session) bool {
    const h = self.header();
    if (h.magic != session.MAGIC or h.version != 1) return false;
    if (h.capacity != session.MAX_ENTRIES or h.count > h.capacity) return false;
    if (h.data_offset < session.HEADER_END or h.data_offset > self.map.len) return false;
    return true;
}

pub fn resetHeader(self: *session.Session) void {
    self.header().* = .{
        .magic = session.MAGIC,
        .version = 1,
        .count = 0,
        .capacity = session.MAX_ENTRIES,
        .data_offset = session.HEADER_END,
    };
}

pub fn lookup(self: *session.Session, cmd_hash: u64) ?*session.Entry {
    const slice = self.entrySlice();
    const count = self.header().count;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (slice[i].cmd_hash == cmd_hash) return &slice[i];
    }
    return null;
}

/// Insert or update an entry. Same `cmd_hash` updates the existing slot
/// in place — the new payload is appended to the data region and the
/// entry's offset/length are pointed at it. The old payload becomes
/// unreferenced ("dead") bytes; v1 does not compact.
pub fn insert(
    self: *session.Session,
    cmd_hash: u64,
    out_hash: u64,
    summary: []const u8,
    category: u8,
) !void {
    const h = self.header();
    const ts: u64 = @intCast(std.time.nanoTimestamp());

    if (lookup(self, cmd_hash)) |existing| {
        // In-place reuse when the new payload fits in the old slot.
        // This prevents data_offset exhaustion on repeat inserts.
        if (summary.len <= existing.data_len) {
            @memcpy(self.map[existing.data_off..][0..summary.len], summary);
            existing.out_hash = out_hash;
            existing.timestamp = ts;
            existing.data_len = @intCast(summary.len);
            existing.original_len = @intCast(summary.len);
            existing.category = category;
            return;
        }
        // Larger payload: append at data_offset, strand the old bytes.
        const doff = h.data_offset;
        if (@as(usize, doff) + summary.len > self.map.len) return error.SessionFull;
        @memcpy(self.map[doff..][0..summary.len], summary);
        existing.out_hash = out_hash;
        existing.timestamp = ts;
        existing.data_off = doff;
        existing.data_len = @intCast(summary.len);
        existing.original_len = @intCast(summary.len);
        existing.category = category;
        h.data_offset += @intCast(summary.len);
        return;
    }

    // New entry
    const doff = h.data_offset;
    if (@as(usize, doff) + summary.len > self.map.len) return error.SessionFull;
    if (h.count >= h.capacity) return error.SessionFull;
    @memcpy(self.map[doff..][0..summary.len], summary);
    self.entrySlice()[h.count] = .{
        .cmd_hash = cmd_hash,
        .out_hash = out_hash,
        .timestamp = ts,
        .data_off = doff,
        .data_len = @intCast(summary.len),
        .original_len = @intCast(summary.len),
        .hits = 0,
        .flags = 0,
        .category = category,
    };
    h.count += 1;
    h.data_offset += @intCast(summary.len);
}

pub fn invalidateCategory(self: *session.Session, category: u8) void {
    const slice = self.entrySlice();
    const count = self.header().count;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (slice[i].category == category) slice[i].out_hash = 0;
    }
}
