const std = @import("std");
const session = @import("session.zig");
const compat = @import("compat.zig");

fn openTmp() !session.Session {
    var tmp = std.testing.tmpDir(.{});
    // Note: don't defer cleanup — caller manages lifecycle via close
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(std.testing.io, ".", &buf);
    const path = buf[0..len];
    return session.Session.open(path, std.testing.allocator);
}

test "open creates file with valid header" {
    var s = try openTmp();
    defer s.close();
    try std.testing.expectEqual(session.MAGIC, s.header().magic);
    try std.testing.expectEqual(@as(u16, 0), s.header().count);
}

test "lookup on empty returns null" {
    var s = try openTmp();
    defer s.close();
    try std.testing.expect(s.lookup(12345) == null);
}

test "insert and lookup" {
    var s = try openTmp();
    defer s.close();
    try s.insert(42, 99, "test", 0);
    const e = s.lookup(42) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 99), e.out_hash);
}

test "invalidateCategory zeros hashes" {
    var s = try openTmp();
    defer s.close();
    try s.insert(1, 100, "a", 2);
    try s.insert(2, 200, "b", 2);
    s.invalidateCategory(2);
    try std.testing.expectEqual(@as(u64, 0), s.lookup(1).?.out_hash);
    try std.testing.expectEqual(@as(u64, 0), s.lookup(2).?.out_hash);
}

test "insert same cmd_hash twice updates in place" {
    var s = try openTmp();
    defer s.close();
    try s.insert(7, 11, "first-payload", 1);
    try s.insert(7, 22, "second-payload-much-longer", 1);
    // Still only one entry for that cmd_hash.
    try std.testing.expectEqual(@as(u16, 1), s.header().count);
    const e = s.lookup(7) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 22), e.out_hash);
    const data = s.map[e.data_off..][0..e.data_len];
    try std.testing.expectEqualStrings("second-payload-much-longer", data);
}

test "isExpired fast_changing entry past 30s" {
    var e = std.mem.zeroes(session.Entry);
    e.category = 0; // fast_changing
    e.timestamp = 1;
    const now: i128 = 1 + 31 * std.time.ns_per_s;
    try std.testing.expect(session.isExpired(&e, now));
}

test "isExpired fast_changing entry within 30s" {
    var e = std.mem.zeroes(session.Entry);
    e.category = 0;
    e.timestamp = 1;
    const now: i128 = 1 + 10 * std.time.ns_per_s;
    try std.testing.expect(!session.isExpired(&e, now));
}

test "isExpired immutable never expires" {
    var e = std.mem.zeroes(session.Entry);
    e.category = 3; // immutable
    e.timestamp = 1;
    const now: i128 = 1 + 10_000 * std.time.ns_per_s;
    try std.testing.expect(!session.isExpired(&e, now));
}

test "open recovers from truncated file" {
    var tmp = std.testing.tmpDir(.{});
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(std.testing.io, ".", &buf);
    const path = buf[0..len];
    // Pre-create a runt file (4 bytes < @sizeOf(Header)=16)
    const f = try tmp.dir.createFile(std.testing.io, "ztk-state", .{ .truncate = true });
    try compat.writeFileAll(f, "xy");
    compat.closeFile(f);
    var s = try session.Session.open(path, std.testing.allocator);
    defer s.close();
    try std.testing.expectEqual(session.MAGIC, s.header().magic);
    try std.testing.expectEqual(@as(u16, 0), s.header().count);
}
