const std = @import("std");
const load = @import("permissions_load.zig");
const matchPattern = @import("permissions_match.zig").matchPattern;
const shell = @import("permissions_shell.zig");

pub const Verdict = enum(u8) {
    allow = 0,
    passthrough = 1,
    deny = 2,
    ask = 3,
};

/// Decide whether `command` should be allowed, denied, or asked.
///
/// The command is split on shell compound operators (`&&`, `||`, `|`, `;`)
/// and each segment is checked independently against the deny/ask rules
/// loaded from `settings_paths`. Deny always wins: if any segment matches
/// a deny rule the result is `.deny` even if other segments would have
/// triggered an ask. If at least one segment matches an ask rule (and no
/// segment matches a deny rule) the result is `.ask`. Otherwise `.allow`.
pub fn checkCommand(
    command: []const u8,
    settings_paths: []const []const u8,
    allocator: std.mem.Allocator,
) !Verdict {
    // Defense-in-depth: any shell metacharacter that bypasses our naive
    // compound splitter triggers an immediate deny. This blocks backticks,
    // $(), eval, bash -c, newlines, and background &.
    if (shell.isSuspicious(command)) return .deny;

    const rules = load.loadRules(settings_paths, allocator) catch |err| switch (err) {
        error.MalformedSettings => return .ask,
        else => |e| return e,
    };
    var asked = false;
    var segments = splitCompound(command);
    while (segments.next()) |raw| {
        const seg = std.mem.trim(u8, raw, " \t");
        if (seg.len == 0) continue;
        for (rules.deny) |pat| {
            if (matchPattern(seg, pat)) return .deny;
        }
        for (rules.ask) |pat| {
            if (matchPattern(seg, pat)) {
                asked = true;
                break;
            }
        }
    }
    return if (asked) .ask else .allow;
}

const SegmentIter = struct {
    rest: []const u8,

    fn next(self: *SegmentIter) ?[]const u8 {
        if (self.rest.len == 0) return null;
        var i: usize = 0;
        while (i < self.rest.len) : (i += 1) {
            const c = self.rest[i];
            if ((c == '&' or c == '|') and i + 1 < self.rest.len and self.rest[i + 1] == c) {
                const seg = self.rest[0..i];
                self.rest = self.rest[i + 2 ..];
                return seg;
            }
            if (c == '|' or c == ';') {
                const seg = self.rest[0..i];
                self.rest = self.rest[i + 1 ..];
                return seg;
            }
        }
        const seg = self.rest;
        self.rest = self.rest[self.rest.len..];
        return seg;
    }
};

pub fn splitCompound(command: []const u8) SegmentIter {
    return .{ .rest = command };
}
