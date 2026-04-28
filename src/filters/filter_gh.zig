const std = @import("std");
const compat = @import("../compat.zig");

/// gh (GitHub CLI) output filter. Handles formatted (not JSON) output
/// from `gh pr list`, `gh issue list`, `gh run list`, `gh pr view`,
/// `gh issue view`. Auto-detects based on output shape.
pub fn filterGh(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // List detection: lines starting with #number or tab-separated ID+title
    const looks_like_list = std.mem.indexOf(u8, input, "\t") != null and
        std.mem.indexOf(u8, input, "Showing") != null;
    if (looks_like_list) return compressList(input, allocator);

    // PR/issue view: has "state:" or "title:" fields
    if (std.mem.indexOf(u8, input, "state:") != null or std.mem.indexOf(u8, input, "title:") != null)
        return compressView(input, allocator);

    // Default: cap lines
    return capLines(input, 40, allocator);
}

fn compressList(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "Showing")) continue;
        // Take first two tab-separated fields (id + title)
        var sp = std.mem.tokenizeScalar(u8, line, '\t');
        const id = sp.next() orelse continue;
        const title = sp.next() orelse "";
        const truncated_title = if (title.len > 60) title[0..60] else title;
        try w.print("#{s} {s}\n", .{ id, truncated_title });
        count += 1;
        if (count >= 25) {
            try w.writeAll("[+more]\n");
            break;
        }
    }
    if (count == 0) return allocator.dupe(u8, "gh: no entries");
    return out.toOwnedSlice(allocator);
}

fn compressView(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var body_lines: usize = 0;
    var in_body = false;
    while (it.next()) |line| {
        if (line.len == 0) {
            if (in_body) continue;
            in_body = true;
            try w.writeByte('\n');
            continue;
        }
        // Header fields: key: value lines (before first blank)
        if (!in_body) {
            // Keep key metadata lines
            if (std.mem.indexOf(u8, line, ":") != null) {
                try w.writeAll(line);
                try w.writeByte('\n');
            }
            continue;
        }
        // Body: keep first 15 lines
        if (body_lines >= 15) {
            try w.writeAll("[body truncated]\n");
            return out.toOwnedSlice(allocator);
        }
        try w.writeAll(line);
        try w.writeByte('\n');
        body_lines += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn capLines(input: []const u8, max: usize, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var n: usize = 0;
    while (it.next()) |line| {
        if (n >= max) break;
        try w.writeAll(line);
        try w.writeByte('\n');
        n += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "gh pr list compresses" {
    const input = "Showing 3 pull requests in user/repo\n42\tFix login bug\topen\tuser1\n43\tAdd feature\topen\tuser2\n";
    const r = try filterGh(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "#42") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Fix login bug") != null);
    try std.testing.expect(r.len < input.len);
}

test "gh empty" {
    const r = try filterGh("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
