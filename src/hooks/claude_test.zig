const std = @import("std");
const claude_init = @import("claude_init.zig");
const claude_rewrite = @import("claude_rewrite.zig");

test "runInit writes a fresh settings file into tmpdir" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    const status = try claude_init.writeInit(allocator, settings);
    try std.testing.expectEqual(claude_init.InstallStatus.installed, status);

    var file = try std.fs.cwd().openFile(settings, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"PreToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"ztk rewrite\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"Bash\"") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
}

test "runInit is idempotent when hook is already present" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    _ = try claude_init.writeInit(allocator, settings);
    const status2 = try claude_init.writeInit(allocator, settings);
    try std.testing.expectEqual(claude_init.InstallStatus.already_installed, status2);
}

test "runInit preserves unrelated top-level keys when merging" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    {
        var f = try std.fs.cwd().createFile(settings, .{ .truncate = true });
        defer f.close();
        try f.writeAll("{\"theme\":\"dark\"}");
    }
    _ = try claude_init.writeInit(allocator, settings);

    var f = try std.fs.cwd().openFile(settings, .{});
    defer f.close();
    const bytes = try f.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"theme\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ztk rewrite") != null);
}

test "sample Claude hook JSON yields expected command" {
    const allocator = std.testing.allocator;
    const payload =
        \\{"session_id":"abc","tool_name":"Bash","tool_input":{"command":"ls -la","description":"list"}}
    ;
    const cmd = try claude_rewrite.extractCommand(allocator, payload);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("ls -la", cmd);
}
