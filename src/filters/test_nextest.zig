const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterCargoNextest(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Fast path: no failures.
    if (std.mem.indexOf(u8, input, "FAIL ") == null) {
        return formatPassSummary(input, allocator);
    }
    return formatFailSummary(input, allocator);
}

fn formatPassSummary(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (findSummary(input)) |s| {
        const passed = parsePassed(s);
        return std.fmt.allocPrint(allocator, "cargo nextest: {d} passed", .{passed});
    }
    return allocator.dupe(u8, "cargo nextest: ok");
}

fn formatFailSummary(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var fail_count: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const t = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "Summary [")) break;
        if (std.mem.startsWith(u8, t, "FAIL [")) {
            fail_count += 1;
            if (fail_count <= 5) {
                if (extractTestName(t)) |name| try w.print("FAIL {s}\n", .{name});
            }
        } else if (std.mem.indexOf(u8, t, "panicked at ") != null and fail_count > 0 and fail_count <= 5) {
            try w.print("  {s}\n", .{std.mem.trim(u8, line, " \t")});
        }
    }
    if (fail_count > 5) try w.print("+{d} more failures\n", .{fail_count - 5});
    if (findSummary(input)) |s| try w.print("{s}\n", .{std.mem.trim(u8, s, " \t")});
    return out.toOwnedSlice(allocator);
}

fn parsePassed(line: []const u8) usize {
    // "Summary [   0.192s] 301 tests run: 301 passed, 0 skipped"
    if (std.mem.indexOf(u8, line, " passed")) |i| {
        var start = i;
        while (start > 0 and std.ascii.isDigit(line[start - 1])) start -= 1;
        return std.fmt.parseInt(usize, line[start..i], 10) catch 0;
    }
    return 0;
}

fn findSummary(input: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const t = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "Summary [")) return t;
    }
    return null;
}

fn extractTestName(t: []const u8) ?[]const u8 {
    // "FAIL [   0.006s] (2/4) test-proj tests::failing_test"
    var i: usize = 0;
    while (i < t.len and t[i] != ']') : (i += 1) {}
    if (i >= t.len) return null;
    i += 1; // skip ']'
    while (i < t.len and t[i] == ' ') i += 1;
    if (i < t.len and t[i] == '(') {
        while (i < t.len and t[i] != ')') i += 1;
        if (i < t.len) i += 1;
    }
    while (i < t.len and t[i] == ' ') i += 1;
    if (i >= t.len) return null;
    return std.mem.trim(u8, t[i..], " \t\r");
}

test "all pass returns summary" {
    const input = "    Starting 301 tests across 1 binary\n        PASS [   0.009s] (1/301) test_one\n     Summary [   0.192s] 301 tests run: 301 passed, 0 skipped\n";
    const r = try filterCargoNextest(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("cargo nextest: 301 passed", r);
}

test "failures preserved" {
    const input = "        FAIL [   0.006s] (2/4) test-proj tests::failing\n    thread 'tests::failing' panicked at src/lib.rs:15:9:\n     Summary [   0.007s] 4 tests run: 2 passed, 2 failed, 1 skipped\n";
    const r = try filterCargoNextest(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "tests::failing") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "panicked") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Summary") != null);
}
