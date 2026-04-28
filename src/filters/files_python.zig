const std = @import("std");
const compat = @import("../compat.zig");

/// Filter `python3` script output. Strategy:
///  1. If a traceback is present, keep ONLY the traceback (drops normal stdout).
///  2. If no traceback, passthrough.
///
/// Python tracebacks start with `Traceback (most recent call last):` and
/// end with an exception line like `ValueError: ...`. The frames in between
/// are usually verbose and repetitive; we keep the first 2 frames and the
/// last 2 frames plus the final exception line.
pub fn filterPython(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Find start of first traceback.
    const tb_start = std.mem.indexOf(u8, input, "Traceback (most recent call last):") orelse
        return allocator.dupe(u8, input);

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);

    // Collect traceback lines until we hit a blank line or end-of-input.
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    var it = std.mem.splitScalar(u8, input[tb_start..], '\n');
    while (it.next()) |line| {
        try lines.append(allocator, line);
        // Traceback ends at an exception line (not indented, contains colon)
        if (lines.items.len > 1 and !std.mem.startsWith(u8, line, " ") and
            std.mem.indexOfScalar(u8, line, ':') != null)
            break;
    }

    // Split into frames (each frame = 2 lines: "File ..." then code line)
    // Keep header + first 2 frames + "..." + last 2 frames + exception
    const n = lines.items.len;
    if (n <= 8) {
        for (lines.items) |line| {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    } else {
        // Header (line 0) + first 4 lines (2 frames) + marker + last 5 lines
        for (lines.items[0..5]) |line| {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
        try w.print("  ... [{d} frames omitted]\n", .{(n - 10) / 2});
        for (lines.items[n - 5 ..]) |line| {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

test "python passthrough without traceback" {
    const input = "hello world\nresult: 42\n";
    const r = try filterPython(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}

test "python keeps short traceback" {
    const input =
        \\Traceback (most recent call last):
        \\  File "main.py", line 10, in <module>
        \\    main()
        \\  File "main.py", line 5, in main
        \\    raise ValueError("bad")
        \\ValueError: bad
    ;
    const r = try filterPython(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "Traceback") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "ValueError: bad") != null);
}

test "python truncates long traceback" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
    try w.writeAll("Traceback (most recent call last):\n");
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try w.print("  File \"x.py\", line {d}, in f\n", .{i});
        try w.print("    g()\n", .{});
    }
    try w.writeAll("ValueError: nope\n");

    const r = try filterPython(buf.items, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "Traceback") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "ValueError: nope") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "frames omitted") != null);
    try std.testing.expect(r.len < buf.items.len);
}
