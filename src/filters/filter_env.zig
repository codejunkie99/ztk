const std = @import("std");

/// env command filter. Masks sensitive values and truncates long ones.
/// Sensitive keys (KEY, SECRET, TOKEN, PASSWORD, PASS, API) have their
/// value replaced with <masked>. Others are truncated to 40 chars.
pub fn filterEnv(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (count >= 50) {
            try w.writeAll("[+more env vars]\n");
            break;
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..eq];
        const val = line[eq + 1 ..];

        if (isSensitive(key)) {
            try w.print("{s}=<masked>\n", .{key});
        } else {
            const truncated = if (val.len > 40) val[0..40] else val;
            try w.print("{s}={s}", .{ key, truncated });
            if (val.len > 40) try w.writeAll("...");
            try w.writeByte('\n');
        }
        count += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn isSensitive(key: []const u8) bool {
    const patterns = [_][]const u8{ "KEY", "SECRET", "TOKEN", "PASSWORD", "PASS", "API", "CREDENTIAL", "AUTH" };
    for (patterns) |p| {
        if (containsUpper(key, p)) return true;
    }
    return false;
}

fn containsUpper(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toUpper(haystack[i + j]) != nc) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

test "env masks sensitive keys" {
    const input = "API_KEY=abc123xyz\nPATH=/usr/bin:/bin\nAWS_SECRET=supersecret\n";
    const r = try filterEnv(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "API_KEY=<masked>") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "AWS_SECRET=<masked>") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "PATH=/usr/bin:/bin") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "abc123xyz") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "supersecret") == null);
}

test "env truncates long values" {
    const input = "FOO=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n";
    const r = try filterEnv(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "...") != null);
    try std.testing.expect(r.len < input.len);
}

test "env empty" {
    const r = try filterEnv("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
