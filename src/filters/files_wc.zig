const std = @import("std");
const compat = @import("../compat.zig");

/// Compress `wc` output by stripping the leading whitespace that wc uses
/// for right-aligned columns and the redundant file path at the end. Each
/// line becomes `<lines>L <words>W <bytes>B <path>`.
///
/// Single-file form: `"     118     759    5780 file.zig"` → `"118L 759W 5780B file.zig"`
/// Multi-file form: preserves the total line
pub fn filterWc(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var any = false;

    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (compactLine(trimmed, w)) |_| {
            any = true;
        } else |err| {
            if (err == error.OutOfMemory) return err;
        }
    }

    if (!any) {
        out.deinit(allocator);
        return allocator.dupe(u8, input);
    }
    return out.toOwnedSlice(allocator);
}

fn compactLine(trimmed: []const u8, w: anytype) !void {
    var fields: [5][]const u8 = undefined;
    var n: usize = 0;
    var sp = std.mem.tokenizeAny(u8, trimmed, " \t");
    while (sp.next()) |f| {
        if (n == 5) return;
        fields[n] = f;
        n += 1;
    }
    if (n < 3) return;
    for (fields[0..3]) |f| {
        for (f) |c| if (!std.ascii.isDigit(c)) return;
    }
    const path = if (n >= 4) fields[n - 1] else "";

    // Collapse "total" line to "Σ" to save bytes.
    if (std.mem.eql(u8, path, "total")) {
        try w.print("Σ {s}L {s}W {s}B\n", .{ fields[0], fields[1], fields[2] });
        return;
    }

    try w.print("{s}L {s}W {s}B", .{ fields[0], fields[1], fields[2] });
    if (path.len > 0) {
        const is_numeric = blk: {
            for (path) |c| if (!std.ascii.isDigit(c)) break :blk false;
            break :blk path.len > 0;
        };
        if (!is_numeric) {
            // Strip directory prefix to save bytes: "src/main.zig" → "main.zig"
            const basename = std.fs.path.basename(path);
            try w.print(" {s}", .{basename});
        }
    }
    try w.writeByte('\n');
}

test "wc single file strips directory" {
    const input = "     118     759    5780 src/filters/comptime.zig\n";
    const r = try filterWc(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("118L 759W 5780B comptime.zig\n", r);
}

test "wc no path" {
    const input = "     118     759    5780\n";
    const r = try filterWc(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("118L 759W 5780B\n", r);
}

test "wc multi file collapses total to sigma" {
    const input =
        \\     118     759    5780 a.zig
        \\      50     200    1000 b.zig
        \\     168     959    6780 total
    ;
    const r = try filterWc(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "a.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Σ") != null);
    try std.testing.expect(r.len < input.len);
}

test "wc empty" {
    const r = try filterWc("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
