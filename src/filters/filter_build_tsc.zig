const std = @import("std");

const TscEntry = struct { file: []const u8, count: usize, samples: [3][]const u8 };

pub fn filterTsc(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "tsc: ok");
    var entries: std.ArrayList(TscEntry) = .{};
    defer entries.deinit(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const file = parseTscFile(line) orelse continue;
        try addTsc(&entries, allocator, file, line);
    }
    if (entries.items.len == 0) return allocator.dupe(u8, "tsc: ok");
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    for (entries.items) |e| {
        try w.print("{s}: {d} errors\n", .{ e.file, e.count });
        const n = @min(e.count, 3);
        for (e.samples[0..n]) |s| try w.print("  {s}\n", .{s});
    }
    return out.toOwnedSlice(allocator);
}

fn parseTscFile(line: []const u8) ?[]const u8 {
    const paren = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    if (std.mem.indexOf(u8, line, "): error TS") == null) return null;
    if (paren == 0) return null;
    return line[0..paren];
}

fn addTsc(list: *std.ArrayList(TscEntry), allocator: std.mem.Allocator, file: []const u8, line: []const u8) !void {
    for (list.items) |*e| {
        if (std.mem.eql(u8, e.file, file)) {
            if (e.count < 3) e.samples[e.count] = line;
            e.count += 1;
            return;
        }
    }
    var entry: TscEntry = .{ .file = file, .count = 1, .samples = .{ "", "", "" } };
    entry.samples[0] = line;
    try list.append(allocator, entry);
}
