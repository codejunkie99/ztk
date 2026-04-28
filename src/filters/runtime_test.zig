const std = @import("std");
const compat = @import("../compat.zig");
const runtime = @import("runtime.zig");

const A = std.testing.allocator;

test "make filter strips entering/leaving" {
    const input = "make[1]: Entering directory\ngcc -O2 foo.c\nmake[1]: Leaving directory\n";
    const out = (try runtime.dispatch("make all", input, A)) orelse return error.NoMatch;
    defer A.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "gcc -O2 foo.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Entering") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Leaving") == null);
}

test "make on_empty when all stripped" {
    const input = "make[1]: Entering directory\nmake[1]: Leaving directory\n";
    const out = (try runtime.dispatch("make build", input, A)) orelse return error.NoMatch;
    defer A.free(out);
    try std.testing.expectEqualStrings("make: ok", out);
}

test "df filter limits lines" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(A);
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        try buf.print(A, "line{d}\n", .{i});
    }
    const out = (try runtime.dispatch("df -h", buf.items, A)) orelse return error.NoMatch;
    defer A.free(out);
    var line_count: usize = 1;
    for (out) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 20), line_count);
    try std.testing.expect(std.mem.indexOf(u8, out, "line0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "line19") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "line20") == null);
}

test "no match returns null" {
    const out = try runtime.dispatch("totally_unknown_command", "hello\n", A);
    try std.testing.expect(out == null);
}

test "ping filter caps at 5 lines" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(A);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try buf.print(A, "64 bytes from host: seq={d}\n", .{i});
    }
    const out = (try runtime.dispatch("ping example.com", buf.items, A)) orelse return error.NoMatch;
    defer A.free(out);
    var line_count: usize = 1;
    for (out) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), line_count);
}
