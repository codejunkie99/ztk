const std = @import("std");

/// Tracks the top-N most-frequent file extensions seen in an `ls`
/// listing. Uses a tiny fixed-capacity table so we don't allocate.
/// Extensions are stored as borrowed slices into the original input.
pub const ExtCounts = struct {
    pub const Entry = struct { ext: []const u8, count: usize };
    pub const cap = 8;
    entries: [cap]Entry = undefined,
    len: usize = 0,
    other: usize = 0,

    pub fn record(self: *ExtCounts, name: []const u8) void {
        const ext = extOf(name);
        if (ext.len == 0) {
            self.other += 1;
            return;
        }
        for (self.entries[0..self.len]) |*e| {
            if (std.mem.eql(u8, e.ext, ext)) {
                e.count += 1;
                return;
            }
        }
        if (self.len < cap) {
            self.entries[self.len] = .{ .ext = ext, .count = 1 };
            self.len += 1;
        } else {
            self.other += 1;
        }
    }

    pub fn topThree(self: *const ExtCounts) [3]?Entry {
        var top: [3]?Entry = .{ null, null, null };
        for (self.entries[0..self.len]) |e| {
            insert(&top, e);
        }
        return top;
    }
};

fn insert(top: *[3]?ExtCounts.Entry, e: ExtCounts.Entry) void {
    var slot: usize = 0;
    while (slot < 3) : (slot += 1) {
        if (top[slot] == null or top[slot].?.count < e.count) break;
    }
    if (slot >= 3) return;
    var i: usize = 2;
    while (i > slot) : (i -= 1) top[i] = top[i - 1];
    top[slot] = e;
}

fn extOf(name: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return "";
    if (dot == 0) return ""; // dotfile, no extension
    const rest = name[dot..];
    if (rest.len > 8) return ""; // weird suffix, ignore
    for (rest[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c)) return "";
    }
    return rest;
}

test "ext counts and top-3" {
    var c: ExtCounts = .{};
    c.record("a.zig");
    c.record("b.zig");
    c.record("c.md");
    c.record("README");
    const top = c.topThree();
    try std.testing.expect(top[0] != null);
    try std.testing.expectEqualStrings(".zig", top[0].?.ext);
    try std.testing.expectEqual(@as(usize, 2), top[0].?.count);
    try std.testing.expectEqual(@as(usize, 1), c.other);
}
