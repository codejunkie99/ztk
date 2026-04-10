const std = @import("std");

const Entry = struct { dir: []const u8, count: usize };

pub fn filterFind(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "find: no results");

    var entries: std.ArrayList(Entry) = .{};
    defer entries.deinit(allocator);

    var total: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        total += 1;
        try bump(&entries, allocator, dirname(trimmed));
    }

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    try w.print("{d} files in {d} dirs: ", .{ total, entries.items.len });
    for (entries.items, 0..) |e, i| {
        if (i >= 30) {
            try w.writeAll(", ...");
            break;
        }
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}/ ({d})", .{ e.dir, e.count });
    }
    return out.toOwnedSlice(allocator);
}

fn dirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| {
        return if (slash == 0) "/" else path[0..slash];
    }
    return ".";
}

fn bump(list: *std.ArrayList(Entry), allocator: std.mem.Allocator, dir: []const u8) !void {
    for (list.items) |*e| {
        if (std.mem.eql(u8, e.dir, dir)) {
            e.count += 1;
            return;
        }
    }
    try list.append(allocator, .{ .dir = dir, .count = 1 });
}

test "groups paths by directory" {
    const input =
        \\./src/a.zig
        \\./src/b.zig
        \\./tests/t1.zig
        \\./src/c.zig
    ;
    const r = try filterFind(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "4 files in 2 dirs") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "./src/ (3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "./tests/ (1)") != null);
}

test "bare filenames treated as current dir" {
    const input = "a.txt\nb.txt\n";
    const r = try filterFind(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 files in 1 dirs") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "./ (2)") != null);
}
