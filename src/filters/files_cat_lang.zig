const std = @import("std");

pub const Lang = enum { zig, rust, ts, py, none };

/// Heuristic language detector. Scans up to ~50 non-blank lines and votes
/// for whichever language's signature keywords show up most. Returns
/// `.none` when nothing scores at least 2 hits — that's the signal that
/// the input is not code (or is too short to confidently classify).
pub fn detect(input: []const u8) Lang {
    var scores = [_]usize{ 0, 0, 0, 0 };
    var seen: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (seen >= 50) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        seen += 1;
        scoreLine(t, &scores);
    }
    return pickWinner(scores);
}

fn scoreLine(t: []const u8, scores: *[4]usize) void {
    if (hasZig(t)) scores[0] += 1;
    if (hasRust(t)) scores[1] += 1;
    if (hasTs(t)) scores[2] += 1;
    if (hasPy(t)) scores[3] += 1;
}

fn pickWinner(scores: [4]usize) Lang {
    var best: usize = 0;
    var best_idx: usize = 0;
    for (scores, 0..) |s, i| if (s > best) {
        best = s;
        best_idx = i;
    };
    if (best < 2) return .none;
    return switch (best_idx) {
        0 => .zig,
        1 => .rust,
        2 => .ts,
        3 => .py,
        else => .none,
    };
}

fn hasZig(t: []const u8) bool {
    if (std.mem.indexOf(u8, t, "@import(") != null) return true;
    if (std.mem.startsWith(u8, t, "pub fn ")) return true;
    if (std.mem.startsWith(u8, t, "const ") and std.mem.indexOf(u8, t, " = ") != null) return true;
    return false;
}

fn hasRust(t: []const u8) bool {
    if (std.mem.startsWith(u8, t, "use ") and std.mem.endsWith(u8, t, ";")) return true;
    if (std.mem.startsWith(u8, t, "pub fn ")) return true;
    if (std.mem.startsWith(u8, t, "impl ")) return true;
    if (std.mem.startsWith(u8, t, "fn ") and std.mem.endsWith(u8, t, "{")) return true;
    return false;
}

fn hasTs(t: []const u8) bool {
    if (std.mem.startsWith(u8, t, "import ")) return true;
    if (std.mem.startsWith(u8, t, "export ")) return true;
    if (std.mem.startsWith(u8, t, "function ")) return true;
    if (std.mem.startsWith(u8, t, "interface ")) return true;
    return false;
}

fn hasPy(t: []const u8) bool {
    if (std.mem.startsWith(u8, t, "def ")) return true;
    if (std.mem.startsWith(u8, t, "class ")) return true;
    if (std.mem.startsWith(u8, t, "from ") and std.mem.indexOf(u8, t, " import ") != null) return true;
    return false;
}

test "detect zig from imports and pub fn" {
    const input = "const std = @import(\"std\");\npub fn main() void {}\n";
    try std.testing.expectEqual(Lang.zig, detect(input));
}

test "detect python" {
    const input = "import os\ndef foo():\n    pass\nclass Bar:\n    pass\n";
    try std.testing.expectEqual(Lang.py, detect(input));
}

test "noise stays none" {
    try std.testing.expectEqual(Lang.none, detect("hello world\nthis is text\n"));
}
