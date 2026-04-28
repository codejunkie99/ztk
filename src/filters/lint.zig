const std = @import("std");
const compat = @import("../compat.zig");

pub const Entry = struct { file: []const u8, count: usize };

pub fn filterLint(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "lint: ok");
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);
    var total: usize = 0;
    var errors: usize = 0;
    var warnings: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const file = parseFinding(line) orelse continue;
        try addEntry(&entries, allocator, file);
        total += 1;
        if (std.ascii.indexOfIgnoreCase(line, "error") != null) errors += 1;
        if (std.ascii.indexOfIgnoreCase(line, "warning") != null) warnings += 1;
    }
    if (entries.items.len == 0) return allocator.dupe(u8, "lint: ok");
    return formatOutput(entries.items, total, errors, warnings, allocator);
}

pub fn parseFinding(line: []const u8) ?[]const u8 {
    var s = line;
    if (std.mem.startsWith(u8, s, "--> ")) s = s[4..];
    const c1 = std.mem.indexOfScalar(u8, s, ':') orelse return null;
    if (c1 == 0) return null;
    if (c1 + 1 >= s.len) return null;
    var i = c1 + 1;
    const start = i;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {}
    if (i == start) return null;
    if (i >= s.len or s[i] != ':') return null;
    const file = s[0..c1];
    if (std.mem.indexOfScalar(u8, file, ' ') != null) return null;
    if (file[0] == '[') return null;
    return file;
}

fn addEntry(list: *std.ArrayList(Entry), allocator: std.mem.Allocator, file: []const u8) !void {
    for (list.items) |*e| {
        if (std.mem.eql(u8, e.file, file)) {
            e.count += 1;
            return;
        }
    }
    try list.append(allocator, .{ .file = file, .count = 1 });
}

fn formatOutput(items: []Entry, total: usize, errs: usize, warns: usize, allocator: std.mem.Allocator) ![]const u8 {
    std.mem.sort(Entry, items, {}, cmpDesc);
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.print("{d} issues in {d} files", .{ total, items.len });
    if (errs > 0 or warns > 0) try w.print(" ({d} errors, {d} warnings)", .{ errs, warns });
    try w.writeByte('\n');
    const cap = @min(items.len, 10);
    for (items[0..cap]) |e| try w.print("  {s}: {d}\n", .{ e.file, e.count });
    return out.toOwnedSlice(allocator);
}

fn cmpDesc(_: void, a: Entry, b: Entry) bool {
    return a.count > b.count;
}
