const std = @import("std");

/// Generic log dedup filter. Collapses consecutive identical (or
/// near-identical modulo timestamps) lines to `line [xN]`.
pub fn filterLog(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var prev_canonical: []const u8 = "";
    var prev_line: []const u8 = "";
    var dup: usize = 0;
    var emitted: usize = 0;

    while (it.next()) |line| {
        if (emitted >= 100) break;
        const canonical = stripTimestamp(line);
        if (std.mem.eql(u8, canonical, prev_canonical) and canonical.len > 0) {
            dup += 1;
            prev_line = line;
            continue;
        }
        if (dup > 0) try w.print("  [x{d}]\n", .{dup + 1});
        if (prev_line.len > 0) {
            try w.writeAll(prev_line);
            try w.writeByte('\n');
            emitted += 1;
        }
        prev_canonical = canonical;
        prev_line = line;
        dup = 0;
    }
    if (prev_line.len > 0 and emitted < 100) {
        try w.writeAll(prev_line);
        try w.writeByte('\n');
    }
    if (dup > 0) try w.print("  [x{d}]\n", .{dup + 1});
    return out.toOwnedSlice(allocator);
}

/// Strip leading timestamps of the form `[YYYY-MM-DD...]` or `YYYY-MM-DD HH:MM:SS`
/// so timestamped log lines that are otherwise identical can be deduped.
fn stripTimestamp(line: []const u8) []const u8 {
    if (line.len < 10) return line;
    // Skip leading bracket timestamps
    if (line[0] == '[') {
        if (std.mem.indexOfScalar(u8, line, ']')) |end| {
            return std.mem.trimLeft(u8, line[end + 1 ..], " \t");
        }
    }
    // Skip leading YYYY-MM-DD pattern
    if (std.ascii.isDigit(line[0]) and line[4] == '-' and line[7] == '-') {
        // Walk past the date and time
        var i: usize = 10;
        while (i < line.len and (line[i] == 'T' or line[i] == ' ' or std.ascii.isDigit(line[i]) or line[i] == ':' or line[i] == '.' or line[i] == 'Z')) : (i += 1) {}
        return std.mem.trimLeft(u8, line[i..], " \t");
    }
    return line;
}

test "log dedups identical lines" {
    const input = "error foo\nerror foo\nerror foo\nother\n";
    const r = try filterLog(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "x3") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "other") != null);
}

test "log dedups timestamped lines" {
    const input =
        \\2026-04-08 10:00:00 INFO request received
        \\2026-04-08 10:00:01 INFO request received
        \\2026-04-08 10:00:02 INFO request received
    ;
    const r = try filterLog(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "x3") != null);
}

test "log empty" {
    const r = try filterLog("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
