const std = @import("std");

const noise_dirs = [_][]const u8{
    "node_modules", ".git", "target", "__pycache__",
    ".next",        "dist", "vendor", "build",
};

pub fn isNoise(name: []const u8) bool {
    for (noise_dirs) |n| if (std.mem.eql(u8, name, n)) return true;
    return false;
}

/// Extracts the filename from an `ls -la` line, or falls back to
/// the trimmed line itself for plain `ls` output.
pub fn extractName(line: []const u8) ?[]const u8 {
    var field: usize = 0;
    var i: usize = 0;
    while (i < line.len and field < 8) {
        while (i < line.len and line[i] == ' ') i += 1;
        if (i >= line.len) break;
        while (i < line.len and line[i] != ' ') i += 1;
        field += 1;
    }
    while (i < line.len and line[i] == ' ') i += 1;
    if (field < 8) {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        return if (trimmed.len == 0) null else trimmed;
    }
    if (i >= line.len) return null;
    return std.mem.trimRight(u8, line[i..], " \t\r");
}

test "extractName from ls -la line" {
    const line = "drwxr-xr-x  5 u s  160  Apr  5 16:02 src";
    try std.testing.expectEqualStrings("src", extractName(line).?);
}

test "extractName from plain ls line" {
    try std.testing.expectEqualStrings("README.md", extractName("README.md").?);
}

test "isNoise detects known dirs" {
    try std.testing.expect(isNoise("node_modules"));
    try std.testing.expect(isNoise(".git"));
    try std.testing.expect(!isNoise("src"));
}
