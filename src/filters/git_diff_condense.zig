const std = @import("std");

pub fn condenseLargeDiff(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var total_lines: usize = 0;
    var hunk_lines: usize = 0;
    var truncated_lines: usize = 0;
    var prev_was_change = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (total_lines >= 500) {
            truncated_lines += countRemaining(&it);
            break;
        }
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "diff --git") or std.mem.startsWith(u8, line, "@@")) {
            hunk_lines = 0;
            prev_was_change = false;
            try writeLine(w, line);
            total_lines += 1;
        } else if (line[0] == '+' or line[0] == '-') {
            if (hunk_lines >= 100) {
                truncated_lines += 1;
            } else {
                try writeLine(w, line);
                total_lines += 1;
                hunk_lines += 1;
            }
            prev_was_change = true;
        } else if (line[0] == ' ') {
            if (hunk_lines >= 100) {
                truncated_lines += 1;
            } else if (prev_was_change) {
                try writeLine(w, line);
                total_lines += 1;
                hunk_lines += 1;
                prev_was_change = false;
            } else {
                truncated_lines += 1;
            }
        } else {
            try writeLine(w, line);
            total_lines += 1;
        }
    }
    if (truncated_lines > 0) try w.print("[ztk: {d} lines truncated]\n", .{truncated_lines});
    return out.toOwnedSlice(allocator);
}

fn writeLine(w: anytype, line: []const u8) !void {
    try w.writeAll(line);
    try w.writeByte('\n');
}

fn countRemaining(it: *std.mem.SplitIterator(u8, .scalar)) usize {
    var n: usize = 0;
    while (it.next()) |line| if (line.len > 0) {
        n += 1;
    };
    return n;
}
