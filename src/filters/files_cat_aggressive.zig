const std = @import("std");
const compat = @import("../compat.zig");

/// Aggressive signature extraction: keeps only top-level declarations
/// (pub fn, const, struct/enum/class, import, etc) and drops function
/// bodies. Works for Zig, Rust, TS/JS, and Python source files.
/// Returns null if the input doesn't look like supported code.
pub fn filterCatAggressive(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}!?[]const u8 {
    const lang = detectLang(input) orelse return null;
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var kept: usize = 0;

    while (it.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (trimmed.len == 0) continue;
        if (isSignature(trimmed, lang)) {
            try w.writeAll(line);
            try w.writeByte('\n');
            kept += 1;
        }
    }

    if (kept == 0) {
        out.deinit(allocator);
        return null;
    }
    return try out.toOwnedSlice(allocator);
}

const Lang = enum { zig, rust, ts_js, python };

fn detectLang(input: []const u8) ?Lang {
    // Use scoring — a file is whatever language has the most keyword hits.
    // Scan the entire file: a file where the first 200 lines are comments
    // and imports should still detect correctly from later content.
    var zig_score: usize = 0;
    var rust_score: usize = 0;
    var tsjs_score: usize = 0;
    var py_score: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const t = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "const ") and std.mem.indexOf(u8, t, "@import") != null) zig_score += 2;
        if (std.mem.startsWith(u8, t, "pub fn ")) zig_score += 1;
        if (std.mem.startsWith(u8, t, "use ")) rust_score += 1;
        if (std.mem.startsWith(u8, t, "impl ")) rust_score += 2;
        if (std.mem.startsWith(u8, t, "fn ") and std.mem.indexOf(u8, t, "->") != null) rust_score += 1;
        if (std.mem.startsWith(u8, t, "import ") or std.mem.startsWith(u8, t, "export ")) tsjs_score += 1;
        if (std.mem.startsWith(u8, t, "interface ") or std.mem.startsWith(u8, t, "type ")) tsjs_score += 1;
        if (std.mem.startsWith(u8, t, "def ") or std.mem.startsWith(u8, t, "class ")) py_score += 1;
        if (std.mem.startsWith(u8, t, "from ") and std.mem.indexOf(u8, t, " import ") != null) py_score += 2;
    }

    const max_score = @max(@max(zig_score, rust_score), @max(tsjs_score, py_score));
    if (max_score < 2) return null;
    if (max_score == zig_score) return .zig;
    if (max_score == rust_score) return .rust;
    if (max_score == tsjs_score) return .ts_js;
    return .python;
}

fn isSignature(trimmed: []const u8, lang: Lang) bool {
    return switch (lang) {
        .zig => std.mem.startsWith(u8, trimmed, "pub fn ") or
            std.mem.startsWith(u8, trimmed, "pub const ") or
            std.mem.startsWith(u8, trimmed, "pub var ") or
            std.mem.startsWith(u8, trimmed, "pub inline fn ") or
            std.mem.startsWith(u8, trimmed, "pub extern fn ") or
            std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "fn ") or
            std.mem.startsWith(u8, trimmed, "test "),
        .rust => std.mem.startsWith(u8, trimmed, "pub fn ") or
            std.mem.startsWith(u8, trimmed, "pub struct ") or
            std.mem.startsWith(u8, trimmed, "pub enum ") or
            std.mem.startsWith(u8, trimmed, "pub trait ") or
            std.mem.startsWith(u8, trimmed, "pub const ") or
            std.mem.startsWith(u8, trimmed, "use ") or
            std.mem.startsWith(u8, trimmed, "mod ") or
            std.mem.startsWith(u8, trimmed, "impl "),
        .ts_js => std.mem.startsWith(u8, trimmed, "export ") or
            std.mem.startsWith(u8, trimmed, "import ") or
            std.mem.startsWith(u8, trimmed, "interface ") or
            std.mem.startsWith(u8, trimmed, "type ") or
            std.mem.startsWith(u8, trimmed, "class ") or
            std.mem.startsWith(u8, trimmed, "function "),
        .python => std.mem.startsWith(u8, trimmed, "def ") or
            std.mem.startsWith(u8, trimmed, "class ") or
            std.mem.startsWith(u8, trimmed, "import ") or
            std.mem.startsWith(u8, trimmed, "from "),
    };
}
