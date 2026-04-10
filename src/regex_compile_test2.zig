const std = @import("std");
const compile_mod = @import("regex_compile.zig");
const types = @import("regex_types.zig");
const State = types.State;
const compile = compile_mod.compile;

fn expectKind(s: State, comptime expected: std.meta.Tag(State.Kind)) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(s.kind));
}

test "compile char class" {
    const r = try compile(std.testing.allocator, "\\d");
    defer std.testing.allocator.free(r.states);
    try std.testing.expectEqual(@as(usize, 2), r.states.len);
    try expectKind(r.states[0], .char_class);
    try expectKind(r.states[1], .match);
}

test "compile anchors" {
    const r = try compile(std.testing.allocator, "^abc$");
    defer std.testing.allocator.free(r.states);
    try std.testing.expectEqual(@as(usize, 6), r.states.len);
    try expectKind(r.states[0], .anchor_start);
    try expectKind(r.states[1], .literal);
    try expectKind(r.states[2], .literal);
    try expectKind(r.states[3], .literal);
    try expectKind(r.states[4], .anchor_end);
    try expectKind(r.states[5], .match);
}

test "compile group" {
    const r = try compile(std.testing.allocator, "(ab)");
    defer std.testing.allocator.free(r.states);
    try expectKind(r.states[r.start], .group_start);
    try std.testing.expectEqual(@as(u8, 1), r.num_groups);
    var found_end = false;
    for (r.states) |s| {
        if (s.kind == .group_end) found_end = true;
    }
    try std.testing.expect(found_end);
}

test "compile word boundary" {
    const r = try compile(std.testing.allocator, "\\bfoo\\b");
    defer std.testing.allocator.free(r.states);
    try expectKind(r.states[0], .word_boundary);
    try expectKind(r.states[1], .literal);
    try expectKind(r.states[2], .literal);
    try expectKind(r.states[3], .literal);
    try expectKind(r.states[4], .word_boundary);
    try expectKind(r.states[5], .match);
}

test "compile escaped special chars" {
    const r = try compile(std.testing.allocator, "\\.");
    defer std.testing.allocator.free(r.states);
    try expectKind(r.states[0], .literal);
    try std.testing.expectEqual(@as(u8, '.'), r.states[0].kind.literal);
}

test "compile invalid unclosed paren" {
    const result = compile(std.testing.allocator, "(abc");
    try std.testing.expectError(error.InvalidPattern, result);
}

test "compile escaped backslash" {
    const r = try compile(std.testing.allocator, "\\\\");
    defer std.testing.allocator.free(r.states);
    try expectKind(r.states[0], .literal);
    try std.testing.expectEqual(@as(u8, '\\'), r.states[0].kind.literal);
}
