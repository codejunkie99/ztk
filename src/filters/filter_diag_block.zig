const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterRustc(input: []const u8, ok_message: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, ok_message);
    if (std.mem.indexOf(u8, input, "error") == null and
        std.mem.indexOf(u8, input, "warning") == null)
    {
        return allocator.dupe(u8, ok_message);
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var in_block = false;
    var blocks: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (isNoise(line)) {
            in_block = false;
            continue;
        }
        if (isDiagStart(line)) {
            blocks += 1;
            in_block = blocks <= 50;
            if (in_block) try writeLine(w, std.mem.trimStart(u8, line, " \t"));
            continue;
        }
        if (!in_block or line.len == 0) {
            if (line.len == 0) in_block = false;
            continue;
        }

        if (isLocation(line)) {
            try w.writeAll("  ");
            try writeLine(w, trimLocation(line));
        } else if (caretMessage(line)) |msg| {
            try w.writeAll("  note: ");
            try writeLine(w, msg);
        } else if (isHelp(line)) {
            try w.writeAll("  ");
            try writeLine(w, std.mem.trim(u8, line, " \t"));
        }
    }
    if (blocks > 50) try w.print("+{d} more diagnostics\n", .{blocks - 50});
    const result = try out.toOwnedSlice(allocator);
    if (result.len == 0) {
        allocator.free(result);
        return allocator.dupe(u8, ok_message);
    }
    return result;
}

fn isNoise(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    if (std.mem.startsWith(u8, t, "Compiling")) return true;
    if (std.mem.startsWith(u8, t, "Checking")) return true;
    if (std.mem.startsWith(u8, t, "Downloading")) return true;
    if (std.mem.startsWith(u8, t, "Finished")) return true;
    if (std.mem.startsWith(u8, t, "Fresh")) return true;
    if (std.mem.startsWith(u8, t, "Updating crates.io")) return true;
    if (std.mem.startsWith(u8, t, "error: aborting due to")) return true;
    if (std.mem.startsWith(u8, t, "error: could not compile")) return true;
    return false;
}

fn isDiagStart(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "error[")) return true;
    if (std.mem.startsWith(u8, line, "error:")) return true;
    if (std.mem.startsWith(u8, line, "warning:")) return true;
    if (std.mem.startsWith(u8, line, "warning[")) return true;
    return false;
}

fn isLocation(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "-->");
}

fn trimLocation(line: []const u8) []const u8 {
    const t = std.mem.trimStart(u8, line, " \t");
    if (std.mem.startsWith(u8, t, "-->")) return std.mem.trimStart(u8, t[3..], " \t");
    return t;
}

fn caretMessage(line: []const u8) ?[]const u8 {
    const caret = std.mem.indexOfScalar(u8, line, '^') orelse return null;
    var i = caret;
    while (i < line.len and line[i] == '^') : (i += 1) {}
    const msg = std.mem.trim(u8, line[i..], " \t");
    if (msg.len == 0) return null;
    return msg;
}

fn isHelp(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "help:") or
        std.mem.startsWith(u8, t, "note:");
}

fn writeLine(w: anytype, line: []const u8) error{OutOfMemory}!void {
    try w.writeAll(line);
    try w.writeByte('\n');
}

test "rustc block filter drops cargo noise and keeps diagnostics" {
    const input =
        \\   Checking app v0.1.0
        \\error[E0425]: cannot find value `x`
        \\  --> src/lib.rs:1:1
        \\   |
        \\1  | x
        \\   | ^ not found
        \\error: aborting due to previous error
    ;
    const r = try filterRustc(input, "cargo build: ok", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "Checking") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "aborting due") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/lib.rs:1:1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "not found") != null);
}
