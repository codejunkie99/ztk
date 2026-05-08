const std = @import("std");
const gemini_init = @import("gemini_init.zig");
const claude_rewrite = @import("claude_rewrite.zig");
const compat = @import("../compat.zig");

fn tmpRealPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![]u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(std.testing.io, ".", &buf);
    return allocator.dupe(u8, buf[0..len]);
}

test "writeInit writes a fresh settings.json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings_path = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings_path);

    const status = try gemini_init.writeInit(allocator, settings_path);
    try std.testing.expectEqual(gemini_init.InstallStatus.installed, status);

    const file = try compat.openFile(settings_path, .{});
    defer compat.closeFile(file);
    const bytes = try compat.readFileToEndAlloc(file, allocator, 1 << 20);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"BeforeTool\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"ztk gemini-rewrite\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"run_shell_command\"") != null);

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
    const settings_path = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings_path);

    const s1 = try gemini_init.writeInit(allocator, settings_path);
    try std.testing.expectEqual(gemini_init.InstallStatus.installed, s1);

    const s2 = try gemini_init.writeInit(allocator, settings_path);
    try std.testing.expectEqual(gemini_init.InstallStatus.already_installed, s2);
}

test "extractCommand parses Gemini BeforeTool stdin" {
    const allocator = std.testing.allocator;
    const input = "{\"tool_name\":\"run_shell_command\",\"tool_input\":{\"command\":\"git status\"}}";
    const cmd = try claude_rewrite.extractCommand(allocator, input);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("git status", cmd);
}

test "extractCommand handles nested JSON with extra fields" {
    const allocator = std.testing.allocator;
    const input = "{\"tool_name\":\"run_shell_command\",\"tool_input\":{\"command\":\"ls -la\",\"description\":\"listing files\"},\"some_meta\":123}";
    const cmd = try claude_rewrite.extractCommand(allocator, input);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("ls -la", cmd);
}

test "extractCommand fails on missing tool_input" {
    const allocator = std.testing.allocator;
    const input = "{\"tool_name\":\"run_shell_command\"}";
    try std.testing.expectError(error.MissingField, claude_rewrite.extractCommand(allocator, input));
}

test "extractCommand fails on missing command field" {
    const allocator = std.testing.allocator;
    const input = "{\"tool_name\":\"run_shell_command\",\"tool_input\":{\"description\":\"no command\"}}";
    try std.testing.expectError(error.MissingField, claude_rewrite.extractCommand(allocator, input));
}
