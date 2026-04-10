const std = @import("std");
const compile = @import("regex_compile.zig").compile;
const matcher = @import("regex_match.zig");
const replace = @import("regex_replace.zig");

const A = std.testing.allocator;

fn compileFree(pat: []const u8) !@import("regex_types.zig").CompiledRegex {
    return compile(A, pat);
}

test "isMatch literal" {
    const r = try compileFree("abc");
    defer A.free(r.states);
    try std.testing.expect(try matcher.isMatch(&r, "abc", A));
    try std.testing.expect(!try matcher.isMatch(&r, "abd", A));
}

test "search literal" {
    const r = try compileFree("world");
    defer A.free(r.states);
    try std.testing.expectEqual(@as(?usize, 6), try matcher.search(&r, "hello world", A));
}

test "matches dot" {
    const r = try compileFree("a.c");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "abc", A));
    try std.testing.expect(!try matcher.matches(&r, "ac", A));
}

test "matches alternation" {
    const r = try compileFree("cat|dog");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "cat", A));
    try std.testing.expect(try matcher.matches(&r, "dog", A));
    try std.testing.expect(!try matcher.matches(&r, "fish", A));
}

test "matches star" {
    const r = try compileFree("a*");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "", A));
    try std.testing.expect(try matcher.matches(&r, "aaa", A));
}

test "matches plus" {
    const r = try compileFree("a+");
    defer A.free(r.states);
    try std.testing.expect(!try matcher.matches(&r, "", A));
    try std.testing.expect(try matcher.matches(&r, "aaa", A));
}

test "matches optional" {
    const r = try compileFree("ab?c");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "ac", A));
    try std.testing.expect(try matcher.matches(&r, "abc", A));
}

test "matches char class" {
    const r = try compileFree("\\d+");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "abc123def", A));
    try std.testing.expect(!try matcher.matches(&r, "abcdef", A));
}

test "anchored match" {
    const r = try compileFree("^abc$");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "abc", A));
    try std.testing.expect(!try matcher.matches(&r, "xabc", A));
}

test "no catastrophic backtracking" {
    const r = try compileFree("a?a?a?aaa");
    defer A.free(r.states);
    try std.testing.expect(try matcher.matches(&r, "aaa", A));
}

test "replaceAll basic" {
    const r = try compileFree("foo");
    defer A.free(r.states);
    const out = try replace.replaceAll(&r, "foo bar foo", "X", A);
    defer A.free(out);
    try std.testing.expectEqualStrings("X bar X", out);
}
