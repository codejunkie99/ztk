const std = @import("std");
const stdout = std.fs.File.stdout;

pub const LogEntry = struct {
    command: []const u8,
    original: usize,
    filtered: usize,
    exit_code: u8,
};

pub fn emit(filtered: []const u8, original_len: usize, exit_code: u8, savings_path: ?[]const u8) !void {
    try stdout().writeAll(filtered);
    if (filtered.len == 0 or filtered[filtered.len - 1] != '\n') {
        try stdout().writeAll("\n");
    }
    if (savings_path) |path| {
        logSavings(path, .{
            .command = "",
            .original = original_len,
            .filtered = filtered.len,
            .exit_code = exit_code,
        }) catch {};
    }
}

pub fn emitWithCommand(filtered: []const u8, entry: LogEntry, savings_path: ?[]const u8) !void {
    try stdout().writeAll(filtered);
    if (filtered.len == 0 or filtered[filtered.len - 1] != '\n') {
        try stdout().writeAll("\n");
    }
    if (savings_path) |path| {
        logSavings(path, entry) catch {};
    }
}

fn logSavings(path: []const u8, entry: LogEntry) !void {
    // Ensure parent directory exists
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch {};
    }
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false, .mode = 0o644 });
    defer file.close();
    try file.seekFromEnd(0);
    const ts = std.time.timestamp();
    var buf: [512]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "{d}\t{s}\t{d}\t{d}\t{d}%\texit={d}\n", .{
        ts,
        entry.command,
        entry.original,
        entry.filtered,
        savingsPercent(entry.original, entry.filtered),
        entry.exit_code,
    });
    try file.writeAll(line);
}

pub fn savingsPercent(original: usize, filtered: usize) usize {
    if (original == 0) return 0;
    if (filtered >= original) return 0;
    return (original - filtered) * 100 / original;
}

test "savingsPercent basic" {
    try std.testing.expectEqual(@as(usize, 80), savingsPercent(1000, 200));
}

test "savingsPercent zero original" {
    try std.testing.expectEqual(@as(usize, 0), savingsPercent(0, 0));
}

test "savingsPercent no savings" {
    try std.testing.expectEqual(@as(usize, 0), savingsPercent(100, 100));
}

test "savingsPercent filtered exceeds original" {
    try std.testing.expectEqual(@as(usize, 0), savingsPercent(100, 200));
}
