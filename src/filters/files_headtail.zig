const std = @import("std");
const compat = @import("../compat.zig");

/// `head` and `tail` output is usually already small by nature. Our only
/// job is to cap it at 50 lines and emit a truncation hint if the user
/// asked for more. Large `tail -f` style output gets the middle trimmed.
///
/// Passthrough under 40 lines. Over 40: keep first 20 + last 20 + hint.
pub fn filterHeadTail(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Count lines
    var total: usize = 0;
    for (input) |c| {
        if (c == '\n') total += 1;
    }

    if (total <= 40) return allocator.dupe(u8, input);

    // Split, keep first 20 and last 20
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        try lines.append(allocator, line);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);

    const head_count: usize = 20;
    const tail_start: usize = if (lines.items.len > 20) lines.items.len - 20 else 0;

    for (lines.items[0..head_count]) |line| {
        try w.writeAll(line);
        try w.writeByte('\n');
    }
    try w.print("[ztk: {d} lines truncated]\n", .{lines.items.len - head_count - (lines.items.len - tail_start)});
    for (lines.items[tail_start..]) |line| {
        try w.writeAll(line);
        if (line.len > 0) try w.writeByte('\n');
    }
    return out.toOwnedSlice(allocator);
}

test "head/tail passthrough for small" {
    const input = "line1\nline2\nline3\n";
    const r = try filterHeadTail(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}

test "head/tail truncates large" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
    var i: usize = 0;
    while (i < 100) : (i += 1) try w.print("line{d}\n", .{i});

    const r = try filterHeadTail(buf.items, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "line0") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "line99") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "line50") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "truncated") != null);
    try std.testing.expect(r.len < buf.items.len);
}

test "head/tail empty" {
    const r = try filterHeadTail("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
