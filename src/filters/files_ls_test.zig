const std = @import("std");
const filterLs = @import("files_ls.zig").filterLs;

test "smart mode shows ext counts and top dirs" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    const w = buf.writer(std.testing.allocator);
    try w.writeAll("total 200\n");
    try w.writeAll("drwxr-xr-x 5 u s 160 Apr 5 16:02 filters\n");
    try w.writeAll("drwxr-xr-x 5 u s 160 Apr 5 16:02 simd\n");
    try w.writeAll("drwxr-xr-x 5 u s 160 Apr 5 16:02 hooks\n");
    var i: usize = 0;
    while (i < 12) : (i += 1) try w.print("-rw-r--r-- 1 u s 100 Apr 5 16:02 file{d}.zig\n", .{i});
    const r = try filterLs(buf.items, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "3 dirs, 12 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "12 .zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "filters/") != null);
}

test "ls -la groups dirs and files and skips noise" {
    const input =
        \\total 40
        \\drwxr-xr-x  5 u s  160  Apr  5 16:02 src
        \\drwxr-xr-x  3 u s   96  Apr  5 16:02 node_modules
        \\drwxr-xr-x  3 u s   96  Apr  5 16:02 tests
        \\-rw-r--r--  1 u s  123  Apr  5 16:02 README.md
        \\-rw-r--r--  1 u s   42  Apr  5 16:02 build.zig
    ;
    const r = try filterLs(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 dirs, 2 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "tests/") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "node_modules") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "README.md") != null);
}

test "plain ls output treats lines as names" {
    const input = "src\ntests\nREADME.md\n";
    const r = try filterLs(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "0 dirs, 3 files") != null);
}

test "empty input" {
    const r = try filterLs("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "empty") != null);
}
