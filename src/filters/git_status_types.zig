const std = @import("std");

pub const Counts = struct {
    branch: []const u8 = "unknown",
    staged: usize = 0,
    modified: usize = 0,
    untracked: usize = 0,
    conflicted: usize = 0,

    pub fn total(self: Counts) usize {
        return self.staged + self.modified + self.untracked + self.conflicted;
    }
};

pub fn writeCounts(w: anytype, c: Counts) !void {
    var need_sep = false;
    const pairs = .{
        .{ c.staged, "staged" },
        .{ c.modified, "modified" },
        .{ c.untracked, "untracked" },
        .{ c.conflicted, "conflicted" },
    };
    inline for (pairs) |p| {
        if (p[0] > 0) {
            if (need_sep) try w.writeAll(", ");
            try w.print("{d} {s}", .{ p[0], p[1] });
            need_sep = true;
        }
    }
}
