const std = @import("std");

/// Returns true if `command` matches the glob-style `pattern`.
///
/// Supported syntax:
///   - `*` matches any sequence of characters (including empty), anywhere
///     in the pattern. Supports prefix, suffix, middle, and multiple stars.
///   - `?` matches exactly one character.
///   - Any other character is literal.
///
/// Matching is case-sensitive. Uses recursive descent. For a pattern with
/// N `*` tokens and command length M, worst case is O(N*M).
pub fn matchPattern(command: []const u8, pattern: []const u8) bool {
    return matchImpl(command, 0, pattern, 0);
}

fn matchImpl(cmd: []const u8, ci: usize, pat: []const u8, pi: usize) bool {
    var c = ci;
    var p = pi;
    while (p < pat.len) {
        const pc = pat[p];
        if (pc == '*') {
            // Collapse consecutive stars.
            while (p < pat.len and pat[p] == '*') p += 1;
            if (p == pat.len) return true;
            // Try every possible match position for the rest of the pattern.
            while (c <= cmd.len) : (c += 1) {
                if (matchImpl(cmd, c, pat, p)) return true;
            }
            return false;
        }
        if (c >= cmd.len) return false;
        if (pc == '?' or pc == cmd[c]) {
            c += 1;
            p += 1;
            continue;
        }
        return false;
    }
    return c == cmd.len;
}

test "exact match" {
    try std.testing.expect(matchPattern("git status", "git status"));
    try std.testing.expect(!matchPattern("git status -s", "git status"));
}

test "prefix wildcard match" {
    try std.testing.expect(matchPattern("git push --force", "git push --force*"));
    try std.testing.expect(matchPattern("git push --force origin main", "git push --force*"));
    try std.testing.expect(matchPattern("rm -rf /", "rm -rf*"));
}

test "no match" {
    try std.testing.expect(!matchPattern("git status", "git push --force*"));
    try std.testing.expect(!matchPattern("git pus", "git push*"));
}

test "empty pattern matches only empty command" {
    try std.testing.expect(matchPattern("", ""));
    try std.testing.expect(!matchPattern("anything", ""));
}

test "case sensitive" {
    try std.testing.expect(!matchPattern("Git Status", "git status"));
}

test "star in middle matches anything" {
    try std.testing.expect(matchPattern("git push --force origin", "git *force*"));
    try std.testing.expect(matchPattern("git push origin --force", "git *force*"));
    try std.testing.expect(!matchPattern("git status", "git *force*"));
}

test "question mark matches single char" {
    try std.testing.expect(matchPattern("cat", "c?t"));
    try std.testing.expect(!matchPattern("coat", "c?t"));
}

test "multiple stars" {
    try std.testing.expect(matchPattern("git push --force --no-verify origin main", "git push *force*main"));
}
