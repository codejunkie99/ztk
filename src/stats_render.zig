//! Render the ztk stats dashboard with ANSI colors, efficiency meter,
//! and per-command breakdown table with impact bars.

const std = @import("std");
const parse = @import("stats_parse.zig");

// ANSI color codes
const GREEN = "\x1b[32m";
const CYAN = "\x1b[36m";
const YELLOW = "\x1b[33m";
const WHITE = "\x1b[37;1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";
const GREEN_BG = "\x1b[42;30m";
const DIM_BG = "\x1b[100m";

pub fn renderDashboard(data: *const parse.StatsData, w: anytype) !void {
    try renderHeader(w);
    try renderSummary(w, data);
    try renderMeter(w, data);
    try renderTable(w, data);
}

fn renderHeader(w: anytype) !void {
    try w.writeAll(GREEN ++ "ztk Token Savings (Global Scope)\n" ++ RESET);
    try w.writeAll(GREEN ++ "══════════════════════════════════════════\n\n" ++ RESET);
}

fn renderSummary(w: anytype, d: *const parse.StatsData) !void {
    const saved = d.savedBytes();
    const pct = d.savingsPct();
    var b1: [32]u8 = undefined;
    var b2: [32]u8 = undefined;
    var b3: [32]u8 = undefined;
    var buf: [512]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf,
        WHITE ++ "Total commands:  " ++ RESET ++ "{d}\n" ++
        WHITE ++ "Input tokens:    " ++ RESET ++ "{s}\n" ++
        WHITE ++ "Output tokens:   " ++ RESET ++ "{s}\n" ++
        WHITE ++ "Tokens saved:    " ++ RESET ++ GREEN ++ "{s} ({d}.{d}%)\n" ++ RESET,
    .{
        d.total_commands,
        fmtSizeSmall(&b1, d.total_raw),
        fmtSizeSmall(&b2, d.total_filtered),
        fmtSizeSmall(&b3, saved),
        pct / 10, pct % 10,
    });
    try w.writeAll(s);
}

fn renderMeter(w: anytype, d: *const parse.StatsData) !void {
    const pct = d.savingsPct();
    const filled: usize = @intCast(@min(30, (pct * 30) / 1000));
    try w.writeAll(WHITE ++ "Efficiency meter:" ++ RESET ++ " ");
    try w.writeAll(GREEN_BG);
    var i: usize = 0;
    while (i < filled) : (i += 1) try w.writeAll(" ");
    try w.writeAll(RESET ++ DIM_BG);
    while (i < 30) : (i += 1) try w.writeAll(" ");
    try w.writeAll(RESET);
    var buf: [32]u8 = undefined;
    const label = try std.fmt.bufPrint(&buf, " " ++ GREEN ++ "{d}.{d}%\n\n" ++ RESET, .{ pct / 10, pct % 10 });
    try w.writeAll(label);
}

fn renderTable(w: anytype, d: *const parse.StatsData) !void {
    try w.writeAll(CYAN ++ "By Command\n\n" ++ RESET);
    try w.writeAll(WHITE ++ "  #   Command                    Count   Saved    Avg%   Impact\n" ++ RESET);
    try w.writeAll(DIM ++ "  ─── ────────────────────────── ─────  ──────── ─────  ────────\n" ++ RESET);

    const max_saved = if (d.entries.len > 0) blk: {
        const e = d.entries[0];
        break :blk if (e.raw_bytes > e.filtered_bytes) e.raw_bytes - e.filtered_bytes else 1;
    } else 1;

    const limit = @min(d.entries.len, 15);
    for (d.entries[0..limit], 0..) |e, idx| {
        try renderRow(w, e, idx + 1, max_saved);
    }
    try w.writeAll("\n");
}

fn renderRow(w: anytype, e: parse.CmdEntry, rank: usize, max_saved: u64) !void {
    const saved = if (e.raw_bytes > e.filtered_bytes) e.raw_bytes - e.filtered_bytes else 0;
    const avg_pct: u64 = if (e.raw_bytes > 0) (saved * 1000) / e.raw_bytes else 0;
    const bar_len: usize = if (max_saved > 0) @intCast(@min(8, (saved * 8) / max_saved)) else 0;

    // Color: green for >70%, yellow for 30-70%, dim for <30%
    const color: []const u8 = if (avg_pct >= 700) GREEN else if (avg_pct >= 300) YELLOW else DIM;

    var buf: [256]u8 = undefined;
    var size_buf: [32]u8 = undefined;
    const cmd_display = if (e.command.len > 26) e.command[0..26] else e.command;
    const saved_str = fmtSizeSmall(&size_buf, saved);
    const line = try std.fmt.bufPrint(&buf,
        "  {d: >2}. {s: <26} {d: >5}  {s: >8} ",
    .{ rank, cmd_display, e.count, saved_str });
    try w.writeAll(line);
    try w.writeAll(color);
    var pct_buf: [16]u8 = undefined;
    const pct_s = try std.fmt.bufPrint(&pct_buf, "{d: >3}.{d}%", .{ avg_pct / 10, avg_pct % 10 });
    try w.writeAll(pct_s);
    try w.writeAll(RESET ++ "  ");

    // Impact bar
    try w.writeAll(CYAN);
    var i: usize = 0;
    while (i < bar_len) : (i += 1) try w.writeAll("█");
    try w.writeAll(RESET);
    while (i < 8) : (i += 1) try w.writeAll(DIM ++ "░" ++ RESET);
    try w.writeAll("\n");
}

fn fmtSizeSmall(buf: *[32]u8, bytes: u64) []const u8 {
    if (bytes < 1024) {
        return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "?";
    }
    if (bytes < 1024 * 1024) {
        const kb = bytes * 10 / 1024;
        return std.fmt.bufPrint(buf, "{d}.{d}K", .{ kb / 10, kb % 10 }) catch "?";
    }
    const mb = bytes * 10 / (1024 * 1024);
    return std.fmt.bufPrint(buf, "{d}.{d}M", .{ mb / 10, mb % 10 }) catch "?";
}
