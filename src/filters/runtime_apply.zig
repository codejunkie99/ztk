const std = @import("std");
const compile = @import("../regex_compile.zig").compile;
const matcher = @import("../regex_match.zig");
const ansi = @import("../simd/ansi.zig");
const lines_mod = @import("../simd/lines.zig");
const RuntimeFilterDef = @import("runtime_defs.zig").RuntimeFilterDef;

/// Apply a runtime filter to `input`. Caller owns the returned slice.
pub fn applyFilter(
    def: *const RuntimeFilterDef,
    input: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const stripped = if (def.strip_ansi)
        try ansi.stripAnsi(input, allocator)
    else
        try allocator.dupe(u8, input);
    defer allocator.free(stripped);

    const lines = try lines_mod.splitLines(stripped, allocator);
    defer if (lines.len > 0) allocator.free(lines);

    var kept: std.ArrayList([]const u8) = .{};
    defer kept.deinit(allocator);

    for (lines) |line| {
        if (try shouldDrop(line, def, allocator)) continue;
        try kept.append(allocator, line);
    }

    const limited = applyLimits(kept.items, def);
    return joinOrEmpty(limited, def, allocator);
}

fn shouldDrop(
    line: []const u8,
    def: *const RuntimeFilterDef,
    allocator: std.mem.Allocator,
) !bool {
    for (def.strip_lines) |pat| {
        if (try matchesPattern(pat, line, allocator)) return true;
    }
    if (def.keep_lines.len > 0) {
        var any = false;
        for (def.keep_lines) |pat| {
            if (try matchesPattern(pat, line, allocator)) {
                any = true;
                break;
            }
        }
        if (!any) return true;
    }
    return false;
}

fn matchesPattern(
    pattern: []const u8,
    input: []const u8,
    allocator: std.mem.Allocator,
) !bool {
    var re = try compile(allocator, pattern);
    defer allocator.free(re.states);
    return matcher.matches(&re, input, allocator);
}

fn applyLimits(items: []const []const u8, def: *const RuntimeFilterDef) []const []const u8 {
    var slice = items;
    if (def.max_lines != 0 and slice.len > def.max_lines) {
        slice = slice[0..def.max_lines];
    }
    if (def.tail_lines != 0 and slice.len > def.tail_lines) {
        slice = slice[slice.len - def.tail_lines ..];
    }
    return slice;
}

fn joinOrEmpty(
    items: []const []const u8,
    def: *const RuntimeFilterDef,
    allocator: std.mem.Allocator,
) ![]const u8 {
    if (items.len == 0) return allocator.dupe(u8, def.on_empty);
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    for (items, 0..) |l, idx| {
        if (idx != 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, l);
    }
    return out.toOwnedSlice(allocator);
}
