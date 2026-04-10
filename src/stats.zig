//! `ztk stats` — read the append-only savings log and print aggregate
//! statistics. Log format (tab-separated):
//!   {timestamp}\t{command}\t{original}\t{filtered}\t{pct}%\texit={code}
//!
//! Path: $HOME/.local/share/ztk/savings.log

const std = @import("std");
const stdout = std.fs.File.stdout;
const stderr = std.fs.File.stderr;

pub fn run(allocator: std.mem.Allocator) !u8 {
    const path = try resolveLogPath(allocator);
    defer allocator.free(path);

    const bytes = std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr().writeAll("ztk: no savings log yet. Run some commands with `ztk run ...` first.\n");
            return 0;
        },
        else => return err,
    };
    defer allocator.free(bytes);

    var total_raw: u64 = 0;
    var total_filtered: u64 = 0;
    var total_calls: u64 = 0;
    var top_cmds: std.StringHashMap(u64) = .init(allocator);
    defer top_cmds.deinit();

    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        _ = cols.next() orelse continue; // timestamp
        const cmd = cols.next() orelse continue;
        const raw_str = cols.next() orelse continue;
        const filt_str = cols.next() orelse continue;
        const raw = std.fmt.parseInt(u64, raw_str, 10) catch continue;
        const filt = std.fmt.parseInt(u64, filt_str, 10) catch continue;
        total_raw += raw;
        total_filtered += filt;
        total_calls += 1;
        // Accumulate by command (use cmd bytes as key)
        const gop = try top_cmds.getOrPut(cmd);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += raw - filt;
    }

    const w = stdout();
    try printSummary(w, total_calls, total_raw, total_filtered);
    try printTopCommands(w, &top_cmds);
    return 0;
}

fn resolveLogPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotSet;
    return std.fmt.allocPrint(allocator, "{s}/.local/share/ztk/savings.log", .{home});
}

fn printSummary(w: anytype, calls: u64, raw: u64, filtered: u64) !void {
    const saved = raw - filtered;
    const pct: u64 = if (raw > 0) (saved * 100) / raw else 0;
    var buf: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf,
        \\ztk stats
        \\---------
        \\commands filtered: {d}
        \\raw bytes:         {d}
        \\filtered bytes:    {d}
        \\saved:             {d} bytes ({d}%)
        \\
        \\
    , .{ calls, raw, filtered, saved, pct });
    try w.writeAll(s);
}

fn printTopCommands(w: anytype, map: *std.StringHashMap(u64)) !void {
    try w.writeAll("top commands by bytes saved:\n");
    var it = map.iterator();
    var total_printed: usize = 0;
    while (it.next()) |e| {
        if (total_printed >= 10) break;
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "  {s: <24} {d} bytes\n", .{ e.key_ptr.*, e.value_ptr.* });
        try w.writeAll(line);
        total_printed += 1;
    }
}
