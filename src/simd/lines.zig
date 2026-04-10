const std = @import("std");

/// Split input into lines using SIMD-accelerated newline scanning.
/// Returns a slice of slices, each pointing into the original input
/// (no copies). Caller owns the returned slice array but NOT the
/// individual line contents.
pub fn splitLines(input: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    if (input.len == 0) return &.{};

    // Count newlines (SIMD accelerated)
    var count: usize = 0;
    const Vec = @Vector(16, u8);
    const needle: Vec = @splat(@as(u8, '\n'));
    var i: usize = 0;
    while (i + 16 <= input.len) : (i += 16) {
        const chunk: Vec = input[i..][0..16].*;
        const matches = chunk == needle;
        count += @popCount(@as(u16, @bitCast(matches)));
    }
    while (i < input.len) : (i += 1) {
        if (input[i] == '\n') count += 1;
    }

    // Handle no trailing newline
    if (input.len > 0 and input[input.len - 1] != '\n') count += 1;

    var lines = try allocator.alloc([]const u8, count);
    var line_idx: usize = 0;
    var start: usize = 0;
    for (input, 0..) |byte, idx| {
        if (byte == '\n') {
            lines[line_idx] = input[start..idx];
            line_idx += 1;
            start = idx + 1;
        }
    }
    if (start < input.len) {
        lines[line_idx] = input[start..];
        line_idx += 1;
    }

    return lines[0..line_idx];
}

test "splitLines basic" {
    const input = "line1\nline2\nline3\n";
    const lines = try splitLines(input, std.testing.allocator);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines no trailing newline" {
    const input = "a\nb";
    const lines = try splitLines(input, std.testing.allocator);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 2), lines.len);
}

test "splitLines empty" {
    const lines = try splitLines("", std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), lines.len);
}

test "splitLines single line" {
    const lines = try splitLines("hello", std.testing.allocator);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expectEqualStrings("hello", lines[0]);
}
