const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterNodeTest(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Fast path: all tests passed (no failures)
    if (hasSummary(input) and !hasFailure(input)) {
        return extractPassSummary(input, allocator);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var failure_blocks: usize = 0;
    var context_remaining: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');

    while (it.next()) |line| {
        if (isFailureLine(line)) {
            failure_blocks += 1;
            context_remaining = 6; // failure line + 5 context lines
        }
        if (context_remaining > 0) {
            if (failure_blocks <= 5) {
                try w.writeAll(line);
                try w.writeByte('\n');
            }
            context_remaining -= 1;
        }
    }

    if (failure_blocks > 5) {
        try w.print("+{d} more failures\n", .{failure_blocks - 5});
    }

    // Append summary lines
    var it2 = std.mem.splitScalar(u8, input, '\n');
    while (it2.next()) |line| {
        if (isSummaryLine(line)) {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn hasFailure(input: []const u8) bool {
    // Case-insensitive check for "FAIL" or "fail"
    if (std.mem.indexOf(u8, input, "FAIL") != null) return true;
    if (std.mem.indexOf(u8, input, "fail") != null) return true;
    return false;
}

fn hasSummary(input: []const u8) bool {
    if (std.mem.indexOf(u8, input, "Tests:") != null) return true;
    if (std.mem.indexOf(u8, input, "Test Suites:") != null) return true;
    if (std.mem.indexOf(u8, input, "Tests ") != null) return true;
    return false;
}

fn isFailureLine(line: []const u8) bool {
    if (std.mem.indexOf(u8, line, "FAIL") != null) return true;
    if (std.mem.indexOf(u8, line, "\xc3\x97") != null) return true; // U+00D7 ×
    if (std.mem.indexOf(u8, line, "\xe2\x9c\x95") != null) return true; // U+2715 ✕
    if (std.mem.indexOf(u8, line, "\xe2\x9c\x97") != null) return true; // U+2717 ✗
    return false;
}

fn isSummaryLine(line: []const u8) bool {
    if (std.mem.indexOf(u8, line, "Tests:") != null) return true;
    if (std.mem.indexOf(u8, line, "Test Suites:") != null) return true;
    if (std.mem.indexOf(u8, line, "Time:") != null) return true;
    if (std.mem.indexOf(u8, line, "Tests ") != null) return true;
    return false;
}

fn extractPassSummary(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (isSummaryLine(line)) {
            try w.writeAll(std.mem.trim(u8, line, " "));
            try w.writeByte('\n');
        }
    }
    const result = try out.toOwnedSlice(allocator);
    if (result.len == 0) {
        allocator.free(result);
        return allocator.dupe(u8, "node test: ok");
    }
    return result;
}

test "all pass jest format returns compact summary" {
    const input =
        \\PASS ./src/utils.test.js
        \\PASS ./src/app.test.js
        \\
        \\Test Suites:  2 passed, 2 total
        \\Tests:        10 passed, 10 total
        \\Time:         3.456 s
    ;
    const result = try filterNodeTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "Tests:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "10 passed") != null);
}

test "failures show details and summary" {
    const input =
        \\PASS ./src/utils.test.js
        \\FAIL ./src/app.test.js
        \\  ● should render correctly
        \\
        \\    expect(received).toBe(expected)
        \\
        \\    Expected: true
        \\    Received: false
        \\
        \\Test Suites:  1 failed, 1 passed, 2 total
        \\Tests:        1 failed, 9 passed, 10 total
        \\Time:         4.567 s
    ;
    const result = try filterNodeTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "FAIL") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "1 failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Tests:") != null);
}

test "empty input returns empty" {
    const result = try filterNodeTest("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
