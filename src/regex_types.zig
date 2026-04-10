const std = @import("std");

pub const CharClass = enum {
    digit,
    space,
    word,

    pub fn matches(self: CharClass, c: u8) bool {
        return switch (self) {
            .digit => c >= '0' and c <= '9',
            .space => c == ' ' or c == '\t' or c == '\n' or c == '\r',
            .word => (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_',
        };
    }
};

pub const State = struct {
    kind: Kind,
    next: ?u16 = null,
    alt: ?u16 = null,

    pub const Kind = union(enum) {
        literal: u8,
        dot,
        char_class: CharClass,
        split,
        match,
        anchor_start,
        anchor_end,
        word_boundary,
        group_start: u8,
        group_end: u8,
    };
};

pub const CompiledRegex = struct {
    states: []const State,
    start: u16,
    num_groups: u8,
};

pub const Fragment = struct {
    start: u16,
    ends: [8]?u16 = .{null} ** 8,
    end_count: u8 = 0,

    pub fn singleEnd(start: u16, end_idx: u16) Fragment {
        var f = Fragment{ .start = start, .end_count = 1 };
        f.ends[0] = end_idx;
        return f;
    }

    pub fn patch(self: Fragment, states: []State, target: u16) void {
        for (0..self.end_count) |i| {
            if (self.ends[i]) |idx| {
                states[idx].next = target;
            }
        }
    }

    pub fn merge(a: Fragment, b: Fragment, start: u16) !Fragment {
        var f = Fragment{ .start = start, .end_count = 0 };
        const total = a.end_count + b.end_count;
        if (total > 8) return error.PatternTooLong;
        for (0..a.end_count) |i| {
            f.ends[f.end_count] = a.ends[i];
            f.end_count += 1;
        }
        for (0..b.end_count) |i| {
            f.ends[f.end_count] = b.ends[i];
            f.end_count += 1;
        }
        return f;
    }
};

pub const CompileError = error{
    InvalidPattern,
    PatternTooLong,
    TooManyGroups,
    OutOfMemory,
};

test "char_class digit" {
    try std.testing.expect(CharClass.digit.matches('5'));
    try std.testing.expect(!CharClass.digit.matches('a'));
}

test "char_class space" {
    try std.testing.expect(CharClass.space.matches(' '));
    try std.testing.expect(CharClass.space.matches('\t'));
    try std.testing.expect(!CharClass.space.matches('x'));
}

test "char_class word" {
    try std.testing.expect(CharClass.word.matches('a'));
    try std.testing.expect(CharClass.word.matches('Z'));
    try std.testing.expect(CharClass.word.matches('_'));
    try std.testing.expect(!CharClass.word.matches('-'));
}
