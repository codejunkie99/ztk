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
    try w.writeAll(D ++ "  │" ++ R ++ G ++ "  ⚡ ztk Token Savings                        " ++ R ++ D ++ "│\n" ++ R);
    try w.writeAll(D ++ "  ├──────────────────────────────────────────────┤\n" ++ R);

    const s1 = try std.fmt.bufPrint(&buf, D ++ "  │" ++ R ++ "  Commands:  " ++ W ++ "{d: <6}" ++ R ++
        "  Input: " ++ W ++ "{s: <8}" ++ R ++
        "  Output: " ++ W ++ "{s}" ++ R ++ "\n", .{ d.total_commands, fmtSz(&b1, d.total_raw), fmtSz(&b2, d.total_filtered) });
    try w.writeAll(s1);

    const s2 = try std.fmt.bufPrint(&buf, D ++ "  │" ++ R ++ "  Saved:     " ++ G ++ "{s: <6}" ++ R ++
        "  " ++ G ++ "({d}.{d}% reduction)" ++ R ++ "\n", .{ fmtSz(&b3, saved), pct / 10, pct % 10 });
    try w.writeAll(s2);

    // Sparkline meter
    try w.writeAll(D ++ "  │" ++ R ++ "  ");
    const filled: usize = @intCast(@min(40, (pct * 40) / 1000));
    try w.writeAll(SPARK);
    var i: usize = 0;
    while (i < filled) : (i += 1) try w.writeAll("▓");
    try w.writeAll(D);
    while (i < 40) : (i += 1) try w.writeAll("░");
    try w.writeAll(R);
    const s3 = try std.fmt.bufPrint(&buf, " " ++ G ++ "{d}.{d}%\n" ++ R, .{ pct / 10, pct % 10 });
    try w.writeAll(s3);

    try w.writeAll(D ++ "  └──────────────────────────────────────────────┘\n" ++ R);
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
