const std = @import("std");
const compat = @import("../compat.zig");

const State = enum { header, progress, failures, summary };

pub fn filterPytest(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Fast path: all tests passed
    if (std.mem.indexOf(u8, input, "FAILED") == null and
        std.mem.indexOf(u8, input, "ERROR") == null)
    {
        return extractPassSummary(input, allocator);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var state: State = .header;
    var failure_blocks: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');

    while (it.next()) |line| {
        state = transition(state, line);
        switch (state) {
            .header, .progress => continue,
            .failures => {
                if (std.mem.startsWith(u8, line, "___")) failure_blocks += 1;
                if (failure_blocks <= 5) {
                    try w.writeAll(line);
                    try w.writeByte('\n');
                }
            },
            .summary => {
                if (failure_blocks > 5) {
                    try w.print("+{d} more failures\n", .{failure_blocks - 5});
                    failure_blocks = 0;
                }
                try w.writeAll(line);
                try w.writeByte('\n');
            },
        }
    }
    return out.toOwnedSlice(allocator);
}

fn transition(current: State, line: []const u8) State {
    if (std.mem.startsWith(u8, line, "=")) {
        if (std.mem.indexOf(u8, line, "FAILURES") != null) return .failures;
        if (std.mem.indexOf(u8, line, "short test summary") != null) return .summary;
        if (std.mem.indexOf(u8, line, "passed") != null or
            std.mem.indexOf(u8, line, "failed") != null) return .summary;
        if (std.mem.indexOf(u8, line, "test session starts") != null) return .header;
    }
    if (isProgressLine(line)) return .progress;
    return current;
}

fn isProgressLine(line: []const u8) bool {
    if (line.len == 0) return false;
    for (line) |c| {
        if (c != '.' and c != 'F' and c != 'E' and c != 's' and c != 'x') return false;
    }
    return true;
}

fn extractPassSummary(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var last_passed: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, "passed") != null) last_passed = line;
    }
    if (last_passed) |summary| {
        return std.fmt.allocPrint(allocator, "pytest: {s}", .{std.mem.trim(u8, summary, "= ")});
    }
    return allocator.dupe(u8, "pytest: ok");
}

test "all pass returns summary" {
    const input =
        \\============================= test session starts ==============================
        \\platform linux -- Python 3.11.0, pytest-7.4.0
        \\collected 12 items
        \\
        \\tests/test_auth.py ......
        \\tests/test_db.py ......
        \\
        \\============================== 12 passed in 0.45s ==============================
    ;
    const result = try filterPytest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("pytest: 12 passed in 0.45s", result);
}

test "failures show details and summary" {
    const input =
        \\============================= test session starts ==============================
        \\collected 3 items
        \\
        \\tests/test_auth.py .F.
        \\
        \\=================================== FAILURES ===================================
        \\___________________________ test_login_invalid ________________________________
        \\    def test_login_invalid():
        \\>       assert login("bad", "creds") is True
        \\E       AssertionError: assert False is True
        \\
        \\=========================== short test summary info ============================
        \\FAILED tests/test_auth.py::test_login_invalid - AssertionError
        \\========================= 1 failed, 2 passed in 0.32s =========================
    ;
    const result = try filterPytest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "test_login_invalid") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "AssertionError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "1 failed, 2 passed") != null);
    // Header noise stripped
    try std.testing.expect(std.mem.indexOf(u8, result, "test session starts") == null);
}

test "empty input returns empty" {
    const result = try filterPytest("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
