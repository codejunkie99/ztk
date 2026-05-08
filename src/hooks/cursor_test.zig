const std = @import("std");
const cursor_init = @import("cursor_init.zig");
const cursor_rewrite = @import("cursor_rewrite.zig");
const compat = @import("../compat.zig");

fn tmpRealPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![]u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(std.testing.io, ".", &buf);
    return allocator.dupe(u8, buf[0..len]);
}

test "writeInit writes a fresh hooks.json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const hooks_path = try std.fs.path.join(allocator, &.{ base, "hooks.json" });
    defer allocator.free(hooks_path);

    const status = try cursor_init.writeInit(allocator, hooks_path);
    try std.testing.expectEqual(cursor_init.InstallStatus.installed, status);

    const file = try compat.openFile(hooks_path, .{});
    defer compat.closeFile(file);
    const bytes = try compat.readFileToEndAlloc(file, allocator, 1 << 20);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"preToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"ztk cursor-rewrite\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"Shell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"version\"") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
}

test "writeInit is idempotent" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const hooks_path = try std.fs.path.join(allocator, &.{ base, "hooks.json" });
    defer allocator.free(hooks_path);

    _ = try cursor_init.writeInit(allocator, hooks_path);
    const status2 = try cursor_init.writeInit(allocator, hooks_path);
    try std.testing.expectEqual(cursor_init.InstallStatus.already_installed, status2);
}

test "writeInit preserves existing hooks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const hooks_path = try std.fs.path.join(allocator, &.{ base, "hooks.json" });
    defer allocator.free(hooks_path);

    {
        const f = try compat.createFile(hooks_path, .{ .truncate = true });
        defer compat.closeFile(f);
        try compat.writeFileAll(f,
            \\{"version":1,"hooks":{"preToolUse":[{"matcher":"Shell","command":"other-tool","type":"command"}]}}
        );
    }
    const status = try cursor_init.writeInit(allocator, hooks_path);
    try std.testing.expectEqual(cursor_init.InstallStatus.installed, status);

    const f = try compat.openFile(hooks_path, .{});
    defer compat.closeFile(f);
    const bytes = try compat.readFileToEndAlloc(f, allocator, 1 << 20);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "other-tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ztk cursor-rewrite") != null);
}

test "writeInit preserves other event types" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const hooks_path = try std.fs.path.join(allocator, &.{ base, "hooks.json" });
    defer allocator.free(hooks_path);

    {
        const f = try compat.createFile(hooks_path, .{ .truncate = true });
        defer compat.closeFile(f);
        try compat.writeFileAll(f,
            \\{"version":1,"hooks":{"postToolUse":[{"matcher":"Shell","command":"logger","type":"command"}]}}
        );
    }
    _ = try cursor_init.writeInit(allocator, hooks_path);

    const f = try compat.openFile(hooks_path, .{});
    defer compat.closeFile(f);
    const bytes = try compat.readFileToEndAlloc(f, allocator, 1 << 20);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "postToolUse") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "logger") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ztk cursor-rewrite") != null);
}

test "extractCommand parses Cursor preToolUse input" {
    const allocator = std.testing.allocator;
    const payload =
        \\{"command":"git status -s"}
    ;
    const cmd = try cursor_rewrite.extractCommand(allocator, payload);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("git status -s", cmd);
}

test "extractCommand handles extra fields" {
    const allocator = std.testing.allocator;
    const payload =
        \\{"command":"ls -la","description":"list files","tool_name":"Shell"}
    ;
    const cmd = try cursor_rewrite.extractCommand(allocator, payload);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("ls -la", cmd);
}

test "extractCommand fails on missing command" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingField, cursor_rewrite.extractCommand(allocator, "{}"));
}
