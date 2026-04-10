const std = @import("std");
const ext_mod = @import("files_ls_ext.zig");

/// Smart-mode formatter: emits "N dirs, M files (X .zig, Y other) [d1/, d2/]"
/// Used when the listing has more than 10 files so the LLM doesn't need to see
/// every name. Top 3 extensions by count, top 3 dirs in listing order.
pub fn formatSmart(
    dirs: []const []const u8,
    files: []const []const u8,
    counts: *const ext_mod.ExtCounts,
    allocator: std.mem.Allocator,
) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    try w.print("{d} dirs, {d} files (", .{ dirs.len, files.len });
    const top = counts.topThree();
    var emitted: usize = 0;
    for (top) |maybe| {
        const e = maybe orelse continue;
        if (emitted > 0) try w.writeAll(", ");
        try w.print("{d} {s}", .{ e.count, e.ext });
        emitted += 1;
    }
    const other = countOther(counts, top);
    if (other > 0) {
        if (emitted > 0) try w.writeAll(", ");
        try w.print("{d} other", .{other});
    }
    try w.writeAll(") [");
    var d_emitted: usize = 0;
    for (dirs) |d| {
        if (d_emitted >= 3) break;
        if (d_emitted > 0) try w.writeAll(", ");
        try w.print("{s}/", .{d});
        d_emitted += 1;
    }
    try w.writeByte(']');
    return out.toOwnedSlice(allocator);
}

/// Fallback formatter for short listings (<=10 files): include every dir
/// name and every file name in the original "[name, name, ...]" shape.
pub fn formatVerbose(
    dirs: []const []const u8,
    files: []const []const u8,
    allocator: std.mem.Allocator,
) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    try w.print("{d} dirs, {d} files [", .{ dirs.len, files.len });
    var emitted: usize = 0;
    for (dirs) |d| {
        if (emitted > 0) try w.writeAll(", ");
        try w.print("{s}/", .{d});
        emitted += 1;
    }
    for (files) |f| {
        if (emitted > 0) try w.writeAll(", ");
        try w.writeAll(f);
        emitted += 1;
    }
    try w.writeByte(']');
    return out.toOwnedSlice(allocator);
}

fn countOther(counts: *const ext_mod.ExtCounts, top: [3]?ext_mod.ExtCounts.Entry) usize {
    var other = counts.other;
    for (counts.entries[0..counts.len]) |e| {
        var in_top = false;
        for (top) |maybe| if (maybe) |t| if (std.mem.eql(u8, t.ext, e.ext)) {
            in_top = true;
        };
        if (!in_top) other += e.count;
    }
    return other;
}
