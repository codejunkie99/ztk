const std = @import("std");
const builtin = @import("builtin");
const claude_rewrite = @import("claude_rewrite.zig");
const compat = @import("../compat.zig");

/// Gemini CLI BeforeTool hook entry point.
///
/// Reads the JSON hook payload from stdin, extracts the shell command,
/// and emits a rewrite directive if ztk has a filter for it. Otherwise
/// emits nothing (passthrough).
///
/// Gemini CLI BeforeTool protocol: the hook should exit 0 and communicate
/// its decision via JSON on stdout. Format:
///
///   {"decision": "allow",
///    "hookSpecificOutput": {"tool_input": {"command": "ztk run <original>"}}}
///
/// Empty stdout means "no opinion, let Gemini CLI decide".
/// Gemini's stdin format uses tool_input.command, same as Claude.
pub fn runRewrite(allocator: std.mem.Allocator) !u8 {
    const stdin_bytes = readStdin(allocator) catch return 0;
    defer allocator.free(stdin_bytes);

    debugLog("called", stdin_bytes) catch {};

    const command = claude_rewrite.extractCommand(allocator, stdin_bytes) catch {
        debugLog("parse-fail", stdin_bytes) catch {};
        return 0;
    };
    defer allocator.free(command);
    if (command.len == 0) {
        debugLog("empty-cmd", "") catch {};
        return 0;
    }

    if (!claude_rewrite.hasFilterFor(command)) {
        debugLog("passthrough", command) catch {};
        return 0;
    }

    debugLog("rewrite", command) catch {};
    try emitRewrite(allocator, command);
    return 0;
}

fn debugLog(kind: []const u8, detail: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const env_key = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    const home = compat.getEnvOwned(allocator, env_key) catch return;
    defer allocator.free(home);
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{s}/.local/share/ztk/gemini-hook-debug.log", .{home});
    if (std.fs.path.dirname(path)) |dir| {
        compat.makePath(dir) catch {};
    }
    const f = compat.createFile(path, .{
        .truncate = false,
        .permissions = compat.permissionsFromMode(0o644),
    }) catch return;
    defer compat.closeFile(f);
    const ts = compat.unixTimestamp();
    var line_buf: [1024]u8 = undefined;
    const max_detail = @min(detail.len, 200);
    const line = std.fmt.bufPrint(&line_buf, "{d}\t{s}\t{s}\n", .{ ts, kind, detail[0..max_detail] }) catch return;
    _ = compat.appendFileAll(f, line) catch {};
}

fn readStdin(allocator: std.mem.Allocator) ![]u8 {
    return compat.readStdinAlloc(allocator, 1 << 20);
}

fn emitRewrite(allocator: std.mem.Allocator, command: []const u8) !void {
    const rewritten = try std.fmt.allocPrint(allocator, "ztk run {s}", .{command});
    defer allocator.free(rewritten);
    const escaped = try jsonEscape(allocator, rewritten);
    defer allocator.free(escaped);
    var buf: [8192]u8 = undefined;
    const payload = try std.fmt.bufPrint(
        &buf,
        "{{\"decision\":\"allow\",\"hookSpecificOutput\":{{\"tool_input\":{{\"command\":\"{s}\"}}}}}}\n",
        .{escaped},
    );
    try compat.writeStdout(payload);
}

fn jsonEscape(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    for (input) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
    return out.toOwnedSlice(allocator);
}

test "jsonEscape handles quotes and backslashes" {
    const allocator = std.testing.allocator;
    const out = try jsonEscape(allocator, "cmd \"arg\"\n\\");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("cmd \\\"arg\\\"\\n\\\\", out);
}
