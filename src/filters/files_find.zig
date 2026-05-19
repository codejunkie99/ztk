const std = @import("std");
const compat = @import("../compat.zig");

const Entry = struct { dir: []const u8, count: usize };
const max_paths = 40;

pub fn filterFind(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "find: no results");

    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);

    var total: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        total += 1;
        try bump(&entries, allocator, dirname(trimmed));
        if (paths.items.len < max_paths) try paths.append(allocator, trimmed);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.print("{d} files in {d} dirs: ", .{ total, entries.items.len });
    for (entries.items, 0..) |e, i| {
        if (i >= 30) {
            try w.writeAll(", ...");
            break;
        }
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}/ ({d})", .{ e.dir, e.count });
    }
    if (paths.items.len > 0) {
        try w.writeAll("\npaths:");
        for (paths.items) |path| {
            try w.print("\n- {s}", .{path});
        }
        if (total > paths.items.len) {
            try w.print("\n... {d} more paths", .{total - paths.items.len});
        }
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

test "issue 13 find output preserves paths agent asked for" {
    const input =
        \\/Users/jay/Programming/flutter/Meyers License Server/admin_ui/lib/features/orders/data/orders_repository.dart
        \\/Users/jay/Programming/flutter/Meyers License Server/admin_ui/lib/features/orders/domain/order.dart
        \\/Users/jay/Programming/flutter/Meyers License Server/admin_ui/lib/features/orders/presentation/orders_page.dart
    ;
    const r = try filterFind(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "3 files in 3 dirs") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "orders_repository.dart") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "orders_page.dart") != null);
}
