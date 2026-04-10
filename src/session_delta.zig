const std = @import("std");
const diff = @import("util/diff.zig");

pub fn computeDelta(
    command: []const u8,
    previous: []const u8,
    current: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    if (diff.isIdentical(previous, current)) {
        const preview_len = @min(current.len, 200);
        const result = try std.fmt.allocPrint(allocator, "{s} (unchanged)", .{current[0..preview_len]});
        // Invariant: if result is very short and contains "unchanged",
        // prepend command name so it's self-contained.
        if (result.len < 20 and std.mem.indexOf(u8, result, "unchanged") != null) {
            allocator.free(result);
            return std.fmt.allocPrint(allocator, "{s}: (unchanged)", .{command});
        }
        return result;
    }
    // Output changed — return full new output (no bare delta)
    const copy = try allocator.alloc(u8, current.len);
    @memcpy(copy, current);
    return copy;
}

test "identical output returns unchanged summary" {
    const r = try computeDelta("git status", "3 modified [a.zig, b.zig]", "3 modified [a.zig, b.zig]", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "unchanged") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "3 modified") != null);
}

test "different output returns full new output" {
    const r = try computeDelta("cargo test", "48 passed, 2 failed", "48 passed, 1 failed", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("48 passed, 1 failed", r);
}

test "short unchanged includes command name" {
    const r = try computeDelta("wc", "ok", "ok", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "wc") != null);
}
