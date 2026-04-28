const std = @import("std");
const compat = @import("../compat.zig");

const Entry = struct { file: []const u8, count: usize };

pub fn filterGrep(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "grep: no matches");
    if (countLines(input) < 10) return allocator.dupe(u8, input);

    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);

    var total: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const file = extractFile(line) orelse continue;
        total += 1;
        try bump(&entries, allocator, file);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.print("{d} matches in {d} files: ", .{ total, entries.items.len });
    for (entries.items, 0..) |e, i| {
        if (i >= 30) {
            try w.writeAll(", ...");
            break;
        }
        if (i > 0) try w.writeAll(", ");
        try w.print("{s} ({d})", .{ e.file, e.count });
    }
    return out.toOwnedSlice(allocator);
}

fn countLines(input: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| if (line.len > 0) {
        n += 1;
    };
    return n;
}

fn extractFile(line: []const u8) ?[]const u8 {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    return line[0..colon];
}

fn bump(list: *std.ArrayList(Entry), allocator: std.mem.Allocator, file: []const u8) !void {
    for (list.items) |*e| {
        if (std.mem.eql(u8, e.file, file)) {
            e.count += 1;
            return;
        }
    }
    try list.append(allocator, .{ .file = file, .count = 1 });
}

test "groups matches by filename" {
    const input =
        \\src/a.zig:10:foo
        \\src/a.zig:20:foo
        \\src/b.zig:5:foo
        \\src/a.zig:30:foo
        \\src/b.zig:15:foo
        \\src/c.zig:1:foo
        \\src/c.zig:2:foo
        \\src/c.zig:3:foo
        \\src/c.zig:4:foo
        \\src/c.zig:5:foo
    ;
    const r = try filterGrep(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "10 matches in 3 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "a.zig (3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "b.zig (2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "c.zig (5)") != null);
}

test "small input passthrough" {
    const input = "src/a.zig:1:foo\nsrc/b.zig:2:bar\n";
    const r = try filterGrep(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}
