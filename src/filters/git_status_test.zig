const std = @import("std");
const filterGitStatus = @import("git_status.zig").filterGitStatus;

test "v2 parse fixture" {
    const input =
        \\# branch.oid abc123def456
        \\# branch.head main
        \\# branch.upstream origin/main
        \\# branch.ab +0 -0
        \\1 M. N... 100644 100644 100644 abc123 def456 src/main.zig
        \\1 .M N... 100644 100644 100644 abc123 def456 src/executor.zig
        \\1 A. N... 000000 100644 100644 000000 abc123 src/new_file.zig
        \\? tests/temp.txt
        \\? .env.local
    ;
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "staged") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "untracked") != null);
}

test "clean tree v2" {
    const input = "# branch.oid abc12345678901234567890\n# branch.head develop\n# branch.upstream origin/develop\n# branch.ab +0 -0\n";
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "develop") != null);
}

test "empty input" {
    const result = try filterGitStatus("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "no output") != null);
}

test "small v1 input passes through" {
    const input = "## main...origin/main\n M src/main.rs\n M src/lib.rs\n";
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(input, result);
}

test "v1 mixed parse keeps all files" {
    const input = "## main\nM  staged.rs\n M modified.rs\nA  added.rs\n?? untracked.txt\nM  more1.rs\nM  more2.rs\nM  more3.rs\n";
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "staged") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "untracked") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "staged.rs") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "modified.rs") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "added.rs") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "untracked.txt") != null);
}

test "plain human format with modified file" {
    const input = "On branch main\n" ++
        "Your branch is up to date with 'origin/main'.\n" ++
        "\n" ++
        "Changes not staged for commit:\n" ++
        "  (use \"git add <file>...\") to update what will be committed\n" ++
        "  (use \"git restore <file>...\") to discard changes in working directory\n" ++
        "\tmodified:   src/main.rs\n" ++
        "\n" ++
        "no changes added to commit\n";
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "src/main.rs") != null);
}

test "v1 rename" {
    const input = "## feature/big-rename-branch-name-to-pad-length\nR  old.zig -> new.zig\nM  another-file.zig\n";
    const result = try filterGitStatus(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "feature/big-rename") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "new.zig") != null);
}
