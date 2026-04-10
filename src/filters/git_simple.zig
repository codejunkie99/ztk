const std = @import("std");

pub fn filterGitAdd(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) count += 1;
    }
    return std.fmt.allocPrint(allocator, "ok ({d} files staged)", .{count});
}

pub fn filterGitCommit(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (std.mem.indexOf(u8, input, "nothing to commit") != null) {
        return try allocator.dupe(u8, "ok (nothing to commit)");
    }
    if (std.mem.indexOf(u8, input, "]")) |bracket| {
        const prefix = input[0 .. bracket + 1];
        if (std.mem.lastIndexOfScalar(u8, prefix, ' ')) |space| {
            const hash_end = std.mem.indexOfScalar(u8, prefix[space + 1 ..], ']') orelse prefix.len - space - 1;
            const hash = prefix[space + 1 ..][0..hash_end];
            return std.fmt.allocPrint(allocator, "ok {s}", .{hash});
        }
    }
    return try allocator.dupe(u8, "ok");
}

pub fn filterGitPush(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (std.mem.indexOf(u8, input, "up-to-date") != null) {
        return try allocator.dupe(u8, "ok (up-to-date)");
    }
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "->")) |_| {
            const trimmed = std.mem.trim(u8, line, " \t");
            return std.fmt.allocPrint(allocator, "ok {s}", .{trimmed});
        }
    }
    return try allocator.dupe(u8, "ok");
}

test "git add counts files" {
    const input = " M src/a.zig\n M src/b.zig\n";
    const r = try filterGitAdd(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 files") != null);
}

test "git commit extracts hash" {
    const input = "[main abc1234] fix\n 1 file changed\n";
    const r = try filterGitCommit(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "abc1234") != null);
}

test "git commit nothing to commit" {
    const r = try filterGitCommit("nothing to commit, working tree clean", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("ok (nothing to commit)", r);
}

test "git push extracts branch" {
    const input = "To github.com:user/repo\n   abc..def  main -> main\n";
    const r = try filterGitPush(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "main -> main") != null);
}

test "git push up to date" {
    const r = try filterGitPush("Everything up-to-date\n", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("ok (up-to-date)", r);
}
