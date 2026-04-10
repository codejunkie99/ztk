const std = @import("std");
const compile_mod = @import("regex_compile.zig");
const types = @import("regex_types.zig");
const State = types.State;
const compile = compile_mod.compile;

fn expectKind(s: State, comptime expected: std.meta.Tag(State.Kind)) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(s.kind));
}

test "compile literal" {
    const r = try compile(std.testing.allocator, "abc");
    defer std.testing.allocator.free(r.states);
    try std.testing.expectEqual(@as(usize, 4), r.states.len);
    try expectKind(r.states[0], .literal);
    try expectKind(r.states[1], .literal);
    try expectKind(r.states[2], .literal);
    try expectKind(r.states[3], .match);
}

test "compile dot" {
    const r = try compile(std.testing.allocator, ".");
    defer std.testing.allocator.free(r.states);
    try std.testing.expectEqual(@as(usize, 2), r.states.len);
    try expectKind(r.states[0], .dot);
    try expectKind(r.states[1], .match);
}

test "compile alternation" {
    const r = try compile(std.testing.allocator, "a|b");
    defer std.testing.allocator.free(r.states);
    var has_split = false;
    var has_match = false;
    for (r.states) |s| {
        if (s.kind == .split) has_split = true;
        if (s.kind == .match) has_match = true;
    }
    try std.testing.expect(has_split);
    try std.testing.expect(has_match);
}

test "compile star" {
    const r = try compile(std.testing.allocator, "a*");
    defer std.testing.allocator.free(r.states);
    var found_split = false;
    for (r.states) |s| {
        if (s.kind == .split) {
            found_split = true;
            try std.testing.expect(s.next != null);
        }
    }
    try std.testing.expect(found_split);
}

test "compile plus" {
    const r = try compile(std.testing.allocator, "a+");
    defer std.testing.allocator.free(r.states);
    try expectKind(r.states[r.start], .literal);
    var found_split = false;
    for (r.states) |s| {
        if (s.kind == .split) found_split = true;
    }
    try std.testing.expect(found_split);
}

test "compile optional" {
    const r = try compile(std.testing.allocator, "a?");
    defer std.testing.allocator.free(r.states);
    var found_split = false;
    for (r.states) |s| {
        if (s.kind == .split) found_split = true;
    }
    try std.testing.expect(found_split);
}
