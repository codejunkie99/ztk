const std = @import("std");

/// Returns true if two strings are identical
pub fn isIdentical(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Compute common prefix length in lines
pub fn commonPrefixLines(a_lines: []const []const u8, b_lines: []const []const u8) usize {
    const min = @min(a_lines.len, b_lines.len);
    var i: usize = 0;
    while (i < min and std.mem.eql(u8, a_lines[i], b_lines[i])) : (i += 1) {}
    return i;
}

test "isIdentical same strings" {
    try std.testing.expect(isIdentical("abc", "abc"));
}

test "isIdentical different strings" {
    try std.testing.expect(!isIdentical("abc", "def"));
}

test "commonPrefixLines" {
    const a = [_][]const u8{ "a", "b", "c" };
    const b = [_][]const u8{ "a", "b", "d" };
    try std.testing.expectEqual(@as(usize, 2), commonPrefixLines(&a, &b));
}
