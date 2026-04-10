const std = @import("std");
const types = @import("git_status_types.zig");

/// Parse porcelain v1 (`## branch`, ` M file`, `?? file`).
pub fn parseV1(input: []const u8, st: *types.Counts, files: *std.ArrayList([]const u8), allocator: std.mem.Allocator) error{OutOfMemory}!void {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "## ")) {
            st.branch = parseBranch(line[3..]);
            continue;
        }
        if (line.len < 3) continue;
        const x = line[0];
        const y = line[1];
        if (line[2] != ' ') continue;
        const path = pathPart(line[3..]);
        if (x == '?' and y == '?') {
            st.untracked += 1;
        } else if (isConflict(x, y)) {
            st.conflicted += 1;
        } else {
            if (x != ' ' and x != '?') st.staged += 1;
            if (y != ' ' and y != '?') st.modified += 1;
        }
        if (files.items.len < 15) try files.append(allocator, path);
    }
}

/// Parse plain `git status` human format ("On branch X", "modified: foo").
pub fn parsePlain(input: []const u8, st: *types.Counts, files: *std.ArrayList([]const u8), allocator: std.mem.Allocator) error{OutOfMemory}!void {
    var in_staged = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "On branch ")) {
            st.branch = std.mem.trim(u8, line["On branch ".len..], " \t\r");
            continue;
        }
        if (std.mem.startsWith(u8, line, "Changes to be committed")) {
            in_staged = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "Changes not staged") or
            std.mem.startsWith(u8, line, "Untracked files"))
        {
            in_staged = false;
            continue;
        }
        const t = std.mem.trimLeft(u8, line, " \t");
        const path = extractPlainPath(t) orelse continue;
        if (std.mem.startsWith(u8, t, "modified:")) {
            if (in_staged) st.staged += 1 else st.modified += 1;
        } else if (std.mem.startsWith(u8, t, "new file:") or std.mem.startsWith(u8, t, "deleted:") or std.mem.startsWith(u8, t, "renamed:")) {
            st.staged += 1;
        } else continue;
        if (files.items.len < 15) try files.append(allocator, path);
    }
}

fn parseBranch(rest: []const u8) []const u8 {
    if (std.mem.indexOf(u8, rest, "...")) |i| return rest[0..i];
    if (std.mem.indexOfScalar(u8, rest, ' ')) |i| return rest[0..i];
    return std.mem.trim(u8, rest, " \t\r");
}

fn pathPart(rest: []const u8) []const u8 {
    if (std.mem.indexOf(u8, rest, " -> ")) |i| return rest[i + 4 ..];
    return rest;
}

fn isConflict(x: u8, y: u8) bool {
    return (x == 'U' or y == 'U') or (x == 'A' and y == 'A') or (x == 'D' and y == 'D');
}

fn extractPlainPath(t: []const u8) ?[]const u8 {
    const colon = std.mem.indexOfScalar(u8, t, ':') orelse return null;
    const after = std.mem.trim(u8, t[colon + 1 ..], " \t\r");
    if (after.len == 0) return null;
    return after;
}
