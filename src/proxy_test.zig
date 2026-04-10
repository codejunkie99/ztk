//! End-to-end smoke tests for the runProxy pipeline. We can't easily
//! mock subprocess execution, so the tests use trivial portable shell
//! commands. The proxy module also has its own inline tests; this file
//! exists so the import is wired into the build's test universe.

const std = @import("std");
const proxy = @import("proxy.zig");

test "runProxy echo hello succeeds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try proxy.runProxy(&.{ "echo", "hello" }, arena.allocator());
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "runProxy sh exit 7 returns 7" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try proxy.runProxy(&.{ "sh", "-c", "exit 7" }, arena.allocator());
    try std.testing.expectEqual(@as(u8, 7), code);
}

test "runProxy single-arg true returns 0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try proxy.runProxy(&.{"true"}, arena.allocator());
    try std.testing.expectEqual(@as(u8, 0), code);
}
