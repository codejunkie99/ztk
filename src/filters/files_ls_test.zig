const std = @import("std");
const compat = @import("../compat.zig");
const filterLs = @import("files_ls.zig").filterLs;

test "smart mode shows ext counts and top dirs" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
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

test "issue 13 directory listing preserves design doc filenames" {
    const input =
        \\2026-04-23-order-credential-ingest-design.md
        \\2026-04-23-wc-product-mapping-design.md
        \\2026-04-30-license-expired-state-design.md
        \\2026-04-30-old-credentials-csv-import-design.md
        \\2026-05-05-order-import-normalization-design.md
        \\2026-05-08-credential-match-redirect-design.md
        \\2026-05-10-customer-second-email-design.md
        \\2026-05-11-credential-assignment-review-design.md
        \\2026-05-12-credential-match-alternates-design.md
        \\2026-05-12-old-credentials-import-unlinked-design.md
        \\2026-05-13-customer-match-email-handling-design.md
        \\2026-05-13-pending-filter-checkbox-design.md
        \\2026-05-14-credential-assignment-auto-preselect-design.md
    ;
    const r = try filterLs(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "13 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "2026-04-23-order-credential-ingest-design.md") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "2026-05-14-credential-assignment-auto-preselect-design.md") != null);
}

test "empty input" {
    const r = try filterLs("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "empty") != null);
}
