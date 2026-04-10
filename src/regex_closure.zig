const std = @import("std");
const types = @import("regex_types.zig");
const State = types.State;
const CompiledRegex = types.CompiledRegex;

fn isWordByte(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_';
}

pub fn atWordBoundary(input: []const u8, pos: usize) bool {
    const before = if (pos == 0) false else isWordByte(input[pos - 1]);
    const after = if (pos >= input.len) false else isWordByte(input[pos]);
    return before != after;
}

/// Add `idx` and its epsilon-closure into `set`. Returns true if a match
/// state was reached during the closure walk.
pub fn addState(
    re: *const CompiledRegex,
    set: []bool,
    idx: u16,
    input: []const u8,
    pos: usize,
) bool {
    if (set[idx]) return false;
    set[idx] = true;
    const s = re.states[idx];
    return switch (s.kind) {
        .split => blk: {
            var matched = false;
            if (s.next) |n| matched = addState(re, set, n, input, pos) or matched;
            if (s.alt) |a| matched = addState(re, set, a, input, pos) or matched;
            break :blk matched;
        },
        .group_start, .group_end => followNext(re, set, s, input, pos),
        .anchor_start => if (pos == 0) followNext(re, set, s, input, pos) else false,
        .anchor_end => if (pos == input.len) followNext(re, set, s, input, pos) else false,
        .word_boundary => if (atWordBoundary(input, pos))
            followNext(re, set, s, input, pos)
        else
            false,
        .match => true,
        .literal, .dot, .char_class => false,
    };
}

fn followNext(
    re: *const CompiledRegex,
    set: []bool,
    s: State,
    input: []const u8,
    pos: usize,
) bool {
    if (s.next) |n| return addState(re, set, n, input, pos);
    return false;
}

/// True if state `s` consumes byte `c`.
pub fn stepByte(s: State, c: u8) bool {
    return switch (s.kind) {
        .literal => |lit| lit == c,
        .dot => c != '\n',
        .char_class => |cc| cc.matches(c),
        else => false,
    };
}
