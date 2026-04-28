const std = @import("std");
const compat = @import("../compat.zig");
const filterGitDiff = @import("git_diff.zig").filterGitDiff;

test "small diff passes through unchanged" {
    const input = "diff --git a/f b/f\nindex abc..def\n@@ -1 +1 @@\n-old\n+new\n";
    const result = try filterGitDiff(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "-old") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "+new") != null);
}

test "small diff strips file headers" {
    const input = "diff --git a/foo.rs b/foo.rs\n--- a/foo.rs\n+++ b/foo.rs\n@@ -1,3 +1,4 @@\n fn main() {\n+    println!(\"hello\");\n }\n";
    const result = try filterGitDiff(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "diff --git") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "+    println!") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "--- a/foo.rs") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "+++ b/foo.rs") == null);
}

test "excess context trimmed, changes preserved" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
    try w.writeAll("diff --git a/f b/f\n");
    for (0..5) |_| try w.writeAll(" context\n");
    try w.writeAll("@@ -1,20 +1,20 @@\n");
    for (0..5) |_| try w.writeAll(" context-before\n");
    try w.writeAll("+added line\n");
    for (0..5) |_| try w.writeAll(" context-after\n");
    const input = buf.items;
    const result = try filterGitDiff(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "+added line") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "truncated") != null);
}

test "stat format passthrough" {
    const input = " src/main.zig | 10 ++++\n 2 files changed, 10 insertions\n";
    const result = try filterGitDiff(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(input, result);
}

test "truncation count accuracy" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
    try w.writeAll("diff --git a/f b/f\n");
    try w.writeAll("index abc..def 100644\n");
    try w.writeAll("@@ -1,200 +1,200 @@\n");
    for (0..150) |_| try w.writeAll("+added\n");
    for (0..10) |_| try w.writeAll(" pad\n");
    const input = buf.items;
    const result = try filterGitDiff(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[ztk: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "60 lines truncated]") != null);
}

test "empty input returns empty" {
    const result = try filterGitDiff("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
