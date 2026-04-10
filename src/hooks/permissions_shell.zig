//! Shell metacharacter detection for permission checking.
//!
//! The compound splitter in permissions.zig only handles `&&`, `||`, `|`, `;`.
//! Real shells have many more ways to execute nested commands: backticks,
//! `$(...)`, `eval`, `bash -c`, newlines, background `&`. Rather than write
//! a full shell parser, we reject any command that contains these patterns
//! outright. Callers get back `true` if the command is "suspicious" and
//! should be treated as `.deny` regardless of the rules.

const std = @import("std");

/// Returns true if the command contains shell metacharacters that bypass
/// our naive compound splitter.
pub fn isSuspicious(command: []const u8) bool {
    // Command substitution: backticks and $(...)
    if (std.mem.indexOfScalar(u8, command, '`') != null) return true;
    if (std.mem.indexOf(u8, command, "$(") != null) return true;
    // Process substitution: <(...) >(...)
    if (std.mem.indexOf(u8, command, "<(") != null) return true;
    if (std.mem.indexOf(u8, command, ">(") != null) return true;
    // Newline injection
    if (std.mem.indexOfScalar(u8, command, '\n') != null) return true;
    if (std.mem.indexOfScalar(u8, command, '\r') != null) return true;
    // Wrappers that execute nested commands: eval, bash -c, sh -c, zsh -c
    if (containsWord(command, "eval ")) return true;
    if (std.mem.indexOf(u8, command, "bash -c") != null) return true;
    if (std.mem.indexOf(u8, command, "sh -c") != null) return true;
    if (std.mem.indexOf(u8, command, "zsh -c") != null) return true;
    if (std.mem.indexOf(u8, command, "python -c") != null) return true;
    if (std.mem.indexOf(u8, command, "perl -e") != null) return true;
    // Single-token background operator (single `&` not `&&`)
    if (hasBackgroundAmp(command)) return true;
    return false;
}

fn containsWord(haystack: []const u8, word: []const u8) bool {
    if (std.mem.startsWith(u8, haystack, word)) return true;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, word)) |pos| : (i = pos + 1) {
        if (pos == 0 or haystack[pos - 1] == ' ' or haystack[pos - 1] == '\t') return true;
    }
    return false;
}

fn hasBackgroundAmp(command: []const u8) bool {
    var i: usize = 0;
    while (i < command.len) : (i += 1) {
        if (command[i] != '&') continue;
        // `&&` is logical AND, not backgrounding
        if (i + 1 < command.len and command[i + 1] == '&') {
            i += 1;
            continue;
        }
        // Preceding `&` (already consumed via the skip above means this is a
        // standalone `&`)
        return true;
    }
    return false;
}

test "backticks are suspicious" {
    try std.testing.expect(isSuspicious("git status `rm -rf /`"));
}

test "dollar paren is suspicious" {
    try std.testing.expect(isSuspicious("echo $(whoami)"));
}

test "bash -c is suspicious" {
    try std.testing.expect(isSuspicious("bash -c 'rm -rf /'"));
}

test "eval is suspicious" {
    try std.testing.expect(isSuspicious("eval rm -rf /"));
}

test "newline is suspicious" {
    try std.testing.expect(isSuspicious("git status\nrm -rf /"));
}

test "background ampersand is suspicious" {
    try std.testing.expect(isSuspicious("git status & rm -rf /"));
}

test "logical and is fine" {
    try std.testing.expect(!isSuspicious("git add . && git commit -m ok"));
}

test "pipe is fine" {
    try std.testing.expect(!isSuspicious("git log | head -5"));
}

test "normal command is fine" {
    try std.testing.expect(!isSuspicious("git status"));
    try std.testing.expect(!isSuspicious("cargo test --all"));
}
