const std = @import("std");
const condense = @import("git_diff_condense.zig");

pub fn filterGitDiff(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Passthrough: --stat output is already compact. Requires:
    //  1. No `diff --git` lines (real diffs always have them)
    //  2. A `|` character (stat format uses pipes)
    //  3. A summary line containing both "files changed" AND either
    //     "insertion" or "deletion" (this is how git formats the summary)
    if (std.mem.indexOf(u8, input, "diff --git") == null and
        std.mem.indexOf(u8, input, "|") != null and
        std.mem.indexOf(u8, input, "files changed") != null and
        (std.mem.indexOf(u8, input, "insertion") != null or
            std.mem.indexOf(u8, input, "deletion") != null))
        return allocator.dupe(u8, input);

    // Strip --- / +++ metadata headers first (the filename is already in
    // the `diff --git` line). Then re-evaluate the small-input passthrough
    // against the stripped result.
    const stripped = try stripFileHeaders(input, allocator);
    var line_count: usize = 0;
    for (stripped) |c| {
        if (c == '\n') line_count += 1;
    }
    if (line_count < 10) return stripped;
    defer allocator.free(stripped);

    return condense.condenseLargeDiff(stripped, allocator);
}

fn stripFileHeaders(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (isFileHeader(line)) continue;
        try w.writeAll(line);
        try w.writeByte('\n');
    }
    return out.toOwnedSlice(allocator);
}

fn isFileHeader(line: []const u8) bool {
    // Match exactly `--- ` or `+++ ` (file header), not `----` (quad-dash patch separator).
    if (line.len < 4) return false;
    const ok_dash = line[0] == '-' and line[1] == '-' and line[2] == '-' and line[3] == ' ';
    const ok_plus = line[0] == '+' and line[1] == '+' and line[2] == '+' and line[3] == ' ';
    return ok_dash or ok_plus;
}

test {
    _ = @import("git_diff_test.zig");
}
