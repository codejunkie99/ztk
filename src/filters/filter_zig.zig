const std = @import("std");

/// Filter `zig build` / `zig test` output. Keeps:
///  - error: ... lines
///  - warning: ... lines
///  - "N tests passed" / "N tests failed" summaries
///  - "Build Summary" lines
///  - Continuation lines that belong to an error/warning (start with space
///    or are stack traces with `^` markers)
///
/// Drops:
///  - Progress (e.g., `install`, `compile`, `run test`)
///  - Cache hits
///  - Debug noise
///
/// Fast path: all-clean input (no error/warning) → "zig: ok"
pub fn filterZig(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    const has_error = std.mem.indexOf(u8, input, "error:") != null or
        std.mem.indexOf(u8, input, "error ") != null;
    const has_warning = std.mem.indexOf(u8, input, "warning:") != null;
    const has_fail = std.mem.indexOf(u8, input, "failed") != null;

    if (!has_error and !has_warning and !has_fail) {
        // All clean — return just the summary line if present.
        // Zig build output uses variants: "Build Summary", "N passed", "tests passed".
        const markers = [_][]const u8{ "Build Summary", "passed" };
        for (markers) |marker| {
            if (std.mem.indexOf(u8, input, marker)) |pos| {
                const start = if (std.mem.lastIndexOfScalar(u8, input[0..pos], '\n')) |i| i + 1 else 0;
                const end = std.mem.indexOfScalarPos(u8, input, pos, '\n') orelse input.len;
                return allocator.dupe(u8, input[start..end]);
            }
        }
        return allocator.dupe(u8, "zig: ok");
    }

    // Keep error/warning blocks and summaries
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var in_diag = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (isDiagLine(line)) {
            in_diag = true;
            try w.writeAll(line);
            try w.writeByte('\n');
            continue;
        }
        if (in_diag and isContinuation(line)) {
            try w.writeAll(line);
            try w.writeByte('\n');
            continue;
        }
        in_diag = false;
        if (isSummary(line)) {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn isDiagLine(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "error:") != null or
        std.mem.indexOf(u8, line, "warning:") != null;
}

fn isContinuation(line: []const u8) bool {
    if (line.len == 0) return false;
    return line[0] == ' ' or line[0] == '\t';
}

fn isSummary(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "Build Summary") != null or
        std.mem.indexOf(u8, line, "tests passed") != null or
        std.mem.indexOf(u8, line, "tests failed") != null or
        std.mem.indexOf(u8, line, "test failure") != null;
}

test "zig clean build returns ok" {
    const input =
        \\install
        \\+- install ztk
        \\   +- zig build-exe ztk Debug native 5s
    ;
    const r = try filterZig(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("zig: ok", r);
}

test "zig test passes returns summary" {
    const input =
        \\install
        \\test
        \\+- run test 170 passed 1s MaxRSS:39M
    ;
    const r = try filterZig(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "170 passed") != null);
}

test "zig error preserves error block" {
    const input =
        \\/tmp/foo.zig:42:5: error: expected type 'u32', found '[]const u8'
        \\    return "hello";
        \\           ^~~~~~~
    ;
    const r = try filterZig(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "error: expected") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "return") != null);
}
