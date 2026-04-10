const std = @import("std");
const types = @import("regex_types.zig");
const sim = @import("regex_simulate.zig");
const CompiledRegex = types.CompiledRegex;

/// Returns true if the entire input matches the pattern.
pub fn isMatch(
    re: *const CompiledRegex,
    input: []const u8,
    allocator: std.mem.Allocator,
) !bool {
    const end = try sim.simulate(re, input, 0, allocator);
    return end != null and end.? == input.len;
}

/// Returns the start index of the first match, or null.
pub fn search(
    re: *const CompiledRegex,
    input: []const u8,
    allocator: std.mem.Allocator,
) !?usize {
    var i: usize = 0;
    while (i <= input.len) : (i += 1) {
        if (try sim.simulate(re, input, i, allocator)) |_| return i;
    }
    return null;
}

/// Returns true if any substring matches.
pub fn matches(
    re: *const CompiledRegex,
    input: []const u8,
    allocator: std.mem.Allocator,
) !bool {
    return (try search(re, input, allocator)) != null;
}
