const std = @import("std");
const compat = @import("../compat.zig");
const types = @import("git_status_types.zig");
const v1 = @import("git_status_v1.zig");

pub fn filterGitStatus(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return std.fmt.allocPrint(allocator, "git status: no output", .{});
    // Small inputs: passthrough is always shorter than a structured summary.
    if (input.len < 80) return allocator.dupe(u8, input);

    var counts: types.Counts = .{};
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    switch (detectFormat(input)) {
        .v2 => try parseV2(input, &counts, &files, allocator),
        .v1 => try v1.parseV1(input, &counts, &files, allocator),
        .plain => try v1.parsePlain(input, &counts, &files, allocator),
    }

    if (counts.total() == 0) return std.fmt.allocPrint(allocator, "on {s}: clean", .{counts.branch});

    var parts: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&parts, allocator);
    try w.print("on {s}: ", .{counts.branch});
    try types.writeCounts(w, counts);
    try w.writeAll(" [");
    for (files.items, 0..) |f, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(f);
    }
    try w.writeByte(']');
    return parts.toOwnedSlice(allocator);
}

const Format = enum { v1, v2, plain };

fn detectFormat(input: []const u8) Format {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "# branch.")) return .v2;
        if (std.mem.startsWith(u8, line, "## ")) return .v1;
        if (std.mem.startsWith(u8, line, "On branch ")) return .plain;
        // Single-char status codes followed by space → v1, else v2.
        if (line.len > 2 and line[2] == ' ') return .v1;
        return .v2;
    }
    return .v1;
}

fn parseV2(input: []const u8, c: *types.Counts, files: *std.ArrayList([]const u8), allocator: std.mem.Allocator) error{OutOfMemory}!void {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "# branch.head ")) {
            c.branch = line["# branch.head ".len..];
        } else if (line[0] == '1' and line.len > 3 and line[1] == ' ') {
            v2StagedMod(line[2], line[3], c);
            if (files.items.len < 15) try files.append(allocator, lastField(line));
        } else if (line[0] == '2' and line.len > 3 and line[1] == ' ') {
            v2StagedMod(line[2], line[3], c);
            if (files.items.len < 15) try files.append(allocator, renameFile(line));
        } else if (line[0] == '?' and line.len > 2) {
            c.untracked += 1;
            if (files.items.len < 15) try files.append(allocator, line[2..]);
        } else if (line[0] == 'u' and line.len > 1 and line[1] == ' ') {
            c.conflicted += 1;
            if (files.items.len < 15) try files.append(allocator, lastField(line));
        }
    }
}

fn v2StagedMod(c1: u8, c2: u8, c: *types.Counts) void {
    if (c1 != '.') c.staged += 1;
    if (c2 != '.') c.modified += 1;
}

fn lastField(line: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, line, '\t')) |tab| return line[tab + 1 ..];
    if (std.mem.lastIndexOfScalar(u8, line, ' ')) |sp| return line[sp + 1 ..];
    return line;
}

fn renameFile(line: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, line, '\t')) |tab| return line[tab + 1 ..];
    return lastField(line);
}

test {
    _ = @import("git_status_test.zig");
}
