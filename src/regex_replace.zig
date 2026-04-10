const std = @import("std");
const types = @import("regex_types.zig");
const sim = @import("regex_simulate.zig");
const CompiledRegex = types.CompiledRegex;

/// Replace all non-overlapping matches with `replacement`. Caller owns
/// the returned buffer. Backreferences are not supported in this version.
pub fn replaceAll(
    re: *const CompiledRegex,
    input: []const u8,
    replacement: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i <= input.len) {
        const end_opt = try sim.simulate(re, input, i, allocator);
        if (end_opt) |end| {
            try out.appendSlice(allocator, replacement);
            if (end == i) {
                // Zero-length match: copy current byte (if any) and advance
                // to avoid an infinite loop.
                if (i < input.len) try out.append(allocator, input[i]);
                i += 1;
            } else {
                i = end;
            }
        } else {
            if (i < input.len) try out.append(allocator, input[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}
