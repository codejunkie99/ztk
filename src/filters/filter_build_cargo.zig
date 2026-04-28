const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterCargoBuild(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "cargo build: ok");
    if (std.mem.indexOf(u8, input, "error") == null and
        std.mem.indexOf(u8, input, "warning") == null)
    {
        return allocator.dupe(u8, "cargo build: ok");
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
            if (in_block) try writeLine(w, line);
            continue;
        }
        if (in_block) {
            if (line.len == 0) {
                in_block = false;
                continue;
            }
            if (isContinuation(line)) try writeLine(w, line);
        }
    }
    if (blocks > 50) try w.print("+{d} more diagnostics\n", .{blocks - 50});
    return out.toOwnedSlice(allocator);
}

fn isNoise(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    if (std.mem.startsWith(u8, t, "Compiling")) return true;
    if (std.mem.startsWith(u8, t, "Downloading")) return true;
    if (std.mem.startsWith(u8, t, "Finished")) return true;
    if (std.mem.startsWith(u8, t, "Fresh")) return true;
    if (std.mem.startsWith(u8, t, "Updating crates.io")) return true;
    return false;
}

fn isDiagStart(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "error[")) return true;
    if (std.mem.startsWith(u8, line, "error:")) return true;
    if (std.mem.startsWith(u8, line, "warning:")) return true;
    if (std.mem.startsWith(u8, line, "warning[")) return true;
    return false;
}

fn isContinuation(line: []const u8) bool {
    if (line.len == 0) return false;
    if (line[0] == ' ' or line[0] == '\t') return true;
    // rustc line-number gutter: "10|     code" or "10 |     code"
    var i: usize = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
    if (i == 0) return false;
    while (i < line.len and line[i] == ' ') i += 1;
    return i < line.len and line[i] == '|';
}

fn writeLine(w: anytype, line: []const u8) error{OutOfMemory}!void {
    try w.writeAll(line);
    try w.writeByte('\n');
}
