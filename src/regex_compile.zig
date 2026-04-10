const std = @import("std");
pub const types = @import("regex_types.zig");
pub const parser_mod = @import("regex_parser.zig");
const State = types.State;
const CompiledRegex = types.CompiledRegex;
const CompileError = types.CompileError;
const Parser = parser_mod.Parser;

/// Compile a regex pattern into a Thompson NFA.
/// Caller owns the returned `CompiledRegex.states` slice and must free it.
pub fn compile(
    allocator: std.mem.Allocator,
    pattern: []const u8,
) CompileError!CompiledRegex {
    var p = Parser.init(allocator, pattern);
    errdefer p.deinit();

    const frag = try p.parseAlternation();
    if (p.pos != p.pattern.len) return error.InvalidPattern;

    const match_idx = try p.emit(.match);
    frag.patch(p.states.items, match_idx);

    const owned = p.states.toOwnedSlice(allocator) catch return error.OutOfMemory;
    return .{
        .states = owned,
        .start = frag.start,
        .num_groups = p.num_groups,
    };
}
