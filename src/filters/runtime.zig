const std = @import("std");
const compile = @import("../regex_compile.zig").compile;
const matcher = @import("../regex_match.zig");
const runtime_defs = @import("runtime_defs.zig");
const runtime_apply = @import("runtime_apply.zig");

/// Dispatch a command through the runtime filter engine. Returns the
/// filtered output if any RuntimeFilterDef.command_pattern matches the
/// command. Returns null otherwise. Caller owns the returned buffer.
///
/// Regexes are compiled per-call (v1). Comptime filters take precedence
/// in the main pipeline; this is the long-tail dispatch path.
pub fn dispatch(
    command: []const u8,
    input: []const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    for (&runtime_defs.filters) |*def| {
        if (try commandMatches(def.command_pattern, command, allocator)) {
            return try runtime_apply.applyFilter(def, input, allocator);
        }
    }
    return null;
}

fn commandMatches(
    pattern: []const u8,
    command: []const u8,
    allocator: std.mem.Allocator,
) !bool {
    var re = try compile(allocator, pattern);
    defer allocator.free(re.states);
    return matcher.matches(&re, command, allocator);
}
