//! Render the ztk stats dashboard — boxed TUI layout with sparkline
//! meter, gradient bar, and per-command breakdown.

const std = @import("std");
const parse = @import("stats_parse.zig");

const G = "\x1b[32m"; // green
const C = "\x1b[36m"; // cyan
const Y = "\x1b[33m"; // yellow
const W = "\x1b[37;1m"; // white bold
const D = "\x1b[2m"; // dim
const R = "\x1b[0m"; // reset
const BG = "\x1b[48;5;22m"; // dark green bg
const SPARK = "\x1b[38;5;46m"; // bright green fg
const BOX_INNER_WIDTH: usize = 46;
const SPARK_WIDTH: usize = 36;

pub fn renderDashboard(data: *const parse.StatsData, w: anytype) !void {
    try w.writeAll("\n");
    try renderBox(w, data);
    try w.writeAll("\n");
    try renderTable(w, data);
}

fn renderBox(w: anytype, d: *const parse.StatsData) !void {
    const saved = d.savedBytes();
    const pct = d.savingsPct();
    var b1: [32]u8 = undefined;
    var b2: [32]u8 = undefined;
    var b3: [32]u8 = undefined;
    var buf: [512]u8 = undefined;

    try w.writeAll(D ++ "  ┌──────────────────────────────────────────────┐\n" ++ R);
    try writeBoxStart(w);
    try w.writeAll(G ++ "  ⚡ ztk Token Savings" ++ R);
    try writeBoxEnd(w, 2 + 1 + 1 + "ztk Token Savings".len);
    try w.writeAll(D ++ "  ├──────────────────────────────────────────────┤\n" ++ R);

    const commands = try std.fmt.bufPrint(&buf, "{d}", .{d.total_commands});
    const input = fmtSz(&b1, d.total_raw);
    const output = fmtSz(&b2, d.total_filtered);
    try writeBoxStart(w);
    try w.writeAll("  Commands: ");
    try w.writeAll(W);
    try w.writeAll(commands);
    try w.writeAll(R ++ "  Input: " ++ W);
    try w.writeAll(input);
    try w.writeAll(R ++ "  Output: " ++ W);
    try w.writeAll(output);
    try w.writeAll(R);
    try writeBoxEnd(w, 2 + "Commands: ".len + commands.len + 2 + "Input: ".len + input.len + 2 + "Output: ".len + output.len);

    const saved_str = fmtSz(&b3, saved);
    const pct_str = try std.fmt.bufPrint(&buf, "{d}.{d}%", .{ pct / 10, pct % 10 });
    try writeBoxStart(w);
    try w.writeAll("  Saved: ");
    try w.writeAll(G);
    try w.writeAll(saved_str);
    try w.writeAll(R ++ "  " ++ G ++ "(");
    try w.writeAll(pct_str);
    try w.writeAll(" reduction)" ++ R);
    try writeBoxEnd(w, 2 + "Saved: ".len + saved_str.len + 2 + 1 + pct_str.len + " reduction)".len);

    // Sparkline meter
    try writeBoxStart(w);
    try w.writeAll("  ");
    const filled: usize = @intCast(@min(@as(u64, SPARK_WIDTH), (pct * @as(u64, SPARK_WIDTH)) / 1000));
    try w.writeAll(SPARK);
    var i: usize = 0;
    while (i < filled) : (i += 1) try w.writeAll("▓");
    try w.writeAll(D);
    while (i < SPARK_WIDTH) : (i += 1) try w.writeAll("░");
    try w.writeAll(R);
    try w.writeAll(" " ++ G);
    try w.writeAll(pct_str);
    try w.writeAll(R);
    try writeBoxEnd(w, 2 + SPARK_WIDTH + 1 + pct_str.len);

    try w.writeAll(D ++ "  └──────────────────────────────────────────────┘\n" ++ R);
}

fn writeBoxStart(w: anytype) !void {
    try w.writeAll(D ++ "  │" ++ R);
}

fn writeBoxEnd(w: anytype, visible_width: usize) !void {
    var i = visible_width;
    while (i < BOX_INNER_WIDTH) : (i += 1) {
        try w.writeAll(" ");
    }
    try w.writeAll(D ++ "│\n" ++ R);
}

fn renderTable(w: anytype, d: *const parse.StatsData) !void {
    try w.writeAll(C ++ "  Top Commands\n\n" ++ R);
    try w.writeAll(D ++ "  #  Command                  Count   Saved    Avg%    Impact\n" ++ R);
    try w.writeAll(D ++ "  ── ──────────────────────── ─────  ──────── ──────  ────────────\n" ++ R);

    const max_saved: u64 = if (d.entries.len > 0) blk: {
        const e = d.entries[0];
        break :blk if (e.raw_bytes > e.filtered_bytes) e.raw_bytes - e.filtered_bytes else 1;
    } else 1;

    const limit = @min(d.entries.len, 12);
    for (d.entries[0..limit], 0..) |e, idx| {
        try renderRow(w, e, idx + 1, max_saved);
    }
    try w.writeAll("\n");
}

fn renderRow(w: anytype, e: parse.CmdEntry, rank: usize, max_saved: u64) !void {
    const saved = if (e.raw_bytes > e.filtered_bytes) e.raw_bytes - e.filtered_bytes else 0;
    const avg_pct: u64 = if (e.raw_bytes > 0) (saved * 1000) / e.raw_bytes else 0;
    const bar_len: usize = if (max_saved > 0) @intCast(@min(12, (saved * 12) / max_saved)) else 0;
    const color: []const u8 = if (avg_pct >= 700) G else if (avg_pct >= 300) Y else D;

    var buf: [256]u8 = undefined;
    var sb: [32]u8 = undefined;
    const cmd = if (e.command.len > 24) e.command[0..24] else e.command;
    const line = try std.fmt.bufPrint(&buf, "  {d: >2}. {s: <24} {d: >5}  {s: >8} ", .{ rank, cmd, e.count, fmtSz(&sb, saved) });
    try w.writeAll(line);
    try w.writeAll(color);
    var pb: [16]u8 = undefined;
    try w.writeAll(try std.fmt.bufPrint(&pb, "{d: >3}.{d}%", .{ avg_pct / 10, avg_pct % 10 }));
    try w.writeAll(R ++ "  ");

    // Gradient bar: bright blocks that fade
    var i: usize = 0;
    while (i < bar_len) : (i += 1) {
        const shade: []const u8 = if (i < bar_len / 3) "\x1b[38;5;46m█" else if (i < 2 * bar_len / 3) "\x1b[38;5;34m▓" else "\x1b[38;5;28m▒";
        try w.writeAll(shade);
    }
    try w.writeAll(R);
    while (i < 12) : (i += 1) try w.writeAll(D ++ "·" ++ R);
    try w.writeAll("\n");
}

fn fmtSz(buf: *[32]u8, bytes: u64) []const u8 {
    if (bytes < 1024) return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "?";
    if (bytes < 1024 * 1024) {
        const k = bytes * 10 / 1024;
        return std.fmt.bufPrint(buf, "{d}.{d}K", .{ k / 10, k % 10 }) catch "?";
    }
    const m = bytes * 10 / (1024 * 1024);
    return std.fmt.bufPrint(buf, "{d}.{d}M", .{ m / 10, m % 10 }) catch "?";
}

test "dashboard keeps savings meter inside summary box" {
    const ansi = @import("simd/ansi.zig");
    const TestWriter = struct {
        list: *std.ArrayList(u8),
        allocator: std.mem.Allocator,

        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.allocator, bytes);
        }
    };
    const Utf8 = struct {
        fn countCodepoints(bytes: []const u8) usize {
            var count: usize = 0;
            for (bytes) |byte| {
                if ((byte & 0b1100_0000) != 0b1000_0000) count += 1;
            }
            return count;
        }
    };

    const entries = [_]parse.CmdEntry{};
    const data: parse.StatsData = .{
        .total_commands = 3,
        .total_raw = 112_900,
        .total_filtered = 20_100,
        .entries = &entries,
    };

    var rendered: std.ArrayList(u8) = .empty;
    defer rendered.deinit(std.testing.allocator);
    const writer: TestWriter = .{ .list = &rendered, .allocator = std.testing.allocator };

    try renderDashboard(&data, writer);

    const plain = try ansi.stripAnsi(rendered.items, std.testing.allocator);
    defer std.testing.allocator.free(plain);

    var saw_meter = false;
    var lines = std.mem.splitScalar(u8, plain, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "  │")) continue;

        try std.testing.expect(std.mem.endsWith(u8, line, "│"));
        const right_border = std.mem.lastIndexOf(u8, line, "│").?;
        try std.testing.expectEqual(@as(usize, 2 + 1 + BOX_INNER_WIDTH), Utf8.countCodepoints(line[0..right_border]));
        if (std.mem.indexOf(u8, line, "▓") != null) {
            saw_meter = true;
            try std.testing.expect(std.mem.indexOf(u8, line, "82.1%") != null);
        }
    }
    try std.testing.expect(saw_meter);
}
