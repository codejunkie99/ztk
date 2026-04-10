const std = @import("std");
const lint = @import("lint.zig");

test "eslint output grouped by file" {
    const input =
        \\src/a.ts:10:5: error  Missing semicolon  semi
        \\src/a.ts:12:1: error  Unexpected var  no-var
        \\src/b.ts:3:9: warning  Unused variable  no-unused-vars
    ;
    const r = try lint.filterLint(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/a.ts: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/b.ts: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "3 issues in 2 files") != null);
}

test "empty input is ok" {
    const r = try lint.filterLint("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("lint: ok", r);
}

test "single file with multiple errors" {
    const input =
        \\app.py:1:1: E501 line too long
        \\app.py:5:1: F401 imported but unused
        \\app.py:9:1: E302 expected 2 blank lines
    ;
    const r = try lint.filterLint(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "app.py: 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "3 issues in 1 files") != null);
}

test "mixed formats group correctly" {
    const input =
        \\src/a.ts:10:5: error Missing semicolon
        \\app.py:1:1: E501 line too long
        \\  --> src/main.rs:42:10
        \\pkg/handler.go:7:2: undefined: foo
    ;
    const r = try lint.filterLint(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/a.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "app.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/main.rs") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "pkg/handler.go") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "4 issues in 4 files") != null);
}
