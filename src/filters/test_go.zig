const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterGoTest(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    if (isNdjson(input)) return filterNdjson(input, allocator);
    return filterPlainText(input, allocator);
}

fn isNdjson(input: []const u8) bool {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        return trimmed[0] == '{' and std.mem.indexOf(u8, trimmed, "\"Action\"") != null;
    }
    return false;
}

fn filterNdjson(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');

    // First pass: collect fail names and count pass/fail
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(allocator);
    var output_buf: std.ArrayList(u8) = .empty;
    defer output_buf.deinit(allocator);
    const ob = compat.listWriter(&output_buf, allocator);

    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] != '{') continue;
        const action = extractField(trimmed, "\"Action\":\"") orelse continue;

        if (std.mem.eql(u8, action, "pass")) {
            pass_count += 1;
        } else if (std.mem.eql(u8, action, "fail")) {
            fail_count += 1;
            if (extractField(trimmed, "\"Test\":\"")) |name| {
                if (name.len > 0) {
                    try names.print(allocator, "FAIL: {s}\n", .{name});
                }
            }
        } else if (std.mem.eql(u8, action, "output")) {
            if (extractField(trimmed, "\"Output\":\"")) |raw| {
                try writeUnescaped(ob, raw);
            }
        }
    }

    if (fail_count == 0) {
        out.deinit(allocator);
        return std.fmt.allocPrint(allocator, "go test: {d} passed", .{pass_count});
    }

    try w.writeAll(names.items);
    if (output_buf.items.len > 0) try w.writeAll(output_buf.items);
    try w.print("go test: {d} passed, {d} failed\n", .{ pass_count, fail_count });
    return out.toOwnedSlice(allocator);
}

fn extractField(line: []const u8, key: []const u8) ?[]const u8 {
    const start_idx = (std.mem.indexOf(u8, line, key) orelse return null) + key.len;
    const rest = line[start_idx..];
    const end = std.mem.indexOf(u8, rest, "\"") orelse return null;
    return rest[0..end];
}

fn writeUnescaped(w: anytype, raw: []const u8) error{OutOfMemory}!void {
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            const c: u8 = switch (raw[i + 1]) {
                'n' => '\n',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                else => raw[i + 1],
            };
            try w.writeByte(c);
            i += 1;
        } else {
            try w.writeByte(raw[i]);
        }
    }
}

fn filterPlainText(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "=== RUN")) continue;
        if (std.mem.indexOf(u8, line, "FAIL") != null or
            std.mem.startsWith(u8, line, "---") or
            std.mem.startsWith(u8, line, "ok "))
        {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }
    const result = try out.toOwnedSlice(allocator);
    if (result.len == 0) {
        allocator.free(result);
        return allocator.dupe(u8, "go test: ok");
    }
    return result;
}

test "ndjson all pass returns summary" {
    const input =
        \\{"Time":"2024-01-01T00:00:00Z","Action":"pass","Package":"pkg","Test":"TestFoo","Elapsed":0.1}
        \\{"Time":"2024-01-01T00:00:01Z","Action":"pass","Package":"pkg","Test":"TestBar","Elapsed":0.2}
    ;
    const result = try filterGoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("go test: 2 passed", result);
}

test "ndjson with failures shows details" {
    const input =
        \\{"Time":"2024-01-01T00:00:00Z","Action":"output","Package":"pkg","Test":"TestBar","Output":"    test.go:42: expected X got Y\n"}
        \\{"Time":"2024-01-01T00:00:01Z","Action":"pass","Package":"pkg","Test":"TestFoo","Elapsed":0.1}
        \\{"Time":"2024-01-01T00:00:02Z","Action":"fail","Package":"pkg","Test":"TestBar","Elapsed":0.3}
    ;
    const result = try filterGoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "FAIL: TestBar") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "expected X got Y") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "1 passed, 1 failed") != null);
}

test "plain text filters heuristically" {
    const input =
        \\=== RUN   TestFoo
        \\--- PASS: TestFoo (0.00s)
        \\=== RUN   TestBar
        \\--- FAIL: TestBar (0.01s)
        \\    bar_test.go:10: expected true
        \\FAIL pkg 0.015s
        \\ok  other/pkg 0.003s
    ;
    const result = try filterGoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    // === RUN lines stripped
    try std.testing.expect(std.mem.indexOf(u8, result, "=== RUN") == null);
    // FAIL and --- lines kept
    try std.testing.expect(std.mem.indexOf(u8, result, "--- FAIL: TestBar") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "FAIL pkg") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ok  other/pkg") != null);
}
