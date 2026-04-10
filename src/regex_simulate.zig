const std = @import("std");
const types = @import("regex_types.zig");
const closure = @import("regex_closure.zig");
const CompiledRegex = types.CompiledRegex;

/// Run the NFA over `input` starting at `pos`. Returns the position after
/// the longest match found, or null if no match at `pos`.
///
/// Implementation: parallel Thompson simulation with two bool-array state
/// sets swapped per input byte. O(N*M) with N = input length and
/// M = number of NFA states. No backtracking.
pub fn simulate(
    re: *const CompiledRegex,
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,
) !?usize {
    const n = re.states.len;
    const buf = try allocator.alloc(bool, n * 2);
    defer allocator.free(buf);
    var current = buf[0..n];
    var next = buf[n .. n * 2];
    @memset(current, false);

    var longest: ?usize = null;
    if (closure.addState(re, current, re.start, input, pos)) longest = pos;

    var i: usize = pos;
    while (i < input.len) : (i += 1) {
        @memset(next, false);
        const c = input[i];
        var any = false;
        for (current, 0..) |active, idx| {
            if (!active) continue;
            const s = re.states[idx];
            if (!closure.stepByte(s, c)) continue;
            any = true;
            if (s.next) |nx| {
                if (closure.addState(re, next, nx, input, i + 1)) longest = i + 1;
            }
        }
        const tmp = current;
        current = next;
        next = tmp;
        if (!any) break;
    }
    return longest;
}
