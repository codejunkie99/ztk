const std = @import("std");
const filterGitLog = @import("git_log.zig").filterGitLog;

test "standard multi-line git log to one-line" {
    const input =
        \\commit abcdef1234567890abcdef1234567890abcdef12
        \\Author: Alice <alice@example.com>
        \\Date:   Mon Jan 1 00:00:00 2024 +0000
        \\
        \\    Add feature X
        \\
        \\commit 1234567890abcdef1234567890abcdef12345678
        \\Author: Bob <bob@example.com>
        \\Date:   Sun Dec 31 00:00:00 2023 +0000
        \\
        \\    Fix bug Y
    ;
    const result = try filterGitLog(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "abcdef1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "1234567") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Add feature X") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Fix bug Y") != null);
}

test "already one-line format passthrough" {
    const input = "abcdef1 Add feature X\n1234567 Fix bug Y\n";
    const result = try filterGitLog(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(input, result);
}

test "oneline strips ---END--- separators" {
    const input = "abc1234 feat: x\n---END---\ndef5678 fix: y\n---END---\n";
    const result = try filterGitLog(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "feat: x") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "fix: y") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "---END---") == null);
}

test "oneline strips trailers" {
    const input = "abc1234 chore: bump\nSigned-off-by: Bot <bot@ci>\nCo-authored-by: Human <h@b>\n---END---\n";
    const result = try filterGitLog(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "chore: bump") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Signed-off-by") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Co-authored-by") == null);
}

test "trailer lines stripped" {
    const input =
        \\commit abcdef1234567890abcdef1234567890abcdef12
        \\Author: Alice <alice@example.com>
        \\Date:   Mon Jan 1 00:00:00 2024 +0000
        \\
        \\    Implement feature
        \\
        \\    Signed-off-by: Alice <alice@example.com>
        \\    Co-authored-by: Bob <bob@example.com>
        \\    Reviewed-by: Carol <carol@example.com>
    ;
    const result = try filterGitLog(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "Implement feature") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Signed-off-by") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Co-authored-by") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Reviewed-by") == null);
}

test "empty input returns empty" {
    const result = try filterGitLog("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
