const std = @import("std");
const compat = @import("../compat.zig");
const body = @import("git_log_body.zig");

/// Aggressive compaction: emit only `hash subject` per commit. Drop all
/// headers (Author/Date/Merge), blanks, bodies, trailers, and `---END---`
/// markers. The one-line path keeps the same shape but scrubs any leftover
/// metadata lines. Subject truncated to 72 chars so the result stays tight.
pub fn filterGitLog(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    if (isOneLine(input)) return compactOneLine(input, allocator);

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var commits: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');

    while (it.next()) |line| {
        if (commits >= 50) break;
        if (!body.isCommitHeader(line)) continue;
        const hash = line["commit ".len..][0..7];
        const subject = body.findSubject(&it);
        try w.print("{s} {s}\n", .{ hash, truncate(subject, 72) });
        commits += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn isOneLine(input: []const u8) bool {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len >= 90) return false;
        if (std.mem.startsWith(u8, line, "commit ")) return false;
        if (std.mem.startsWith(u8, line, "Author:")) return false;
        if (std.mem.startsWith(u8, line, "Date:")) return false;
    }
    return true;
}

fn compactOneLine(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "---END---") != null) continue;
        if (body.isHeader(line)) continue;
        if (body.isTrailer(line)) continue;
        try w.writeAll(line);
        try w.writeByte('\n');
    }
    return out.toOwnedSlice(allocator);
}

fn truncate(s: []const u8, max: usize) []const u8 {
    return if (s.len <= max) s else s[0..max];
}

test {
    _ = @import("git_log_test.zig");
}
