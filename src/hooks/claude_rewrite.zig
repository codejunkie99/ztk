const std = @import("std");
const builtin = @import("builtin");
const comptime_filters = @import("../filters/comptime.zig");
const compat = @import("../compat.zig");

/// Claude Code PreToolUse hook entry point.
///
/// Reads the JSON hook payload from stdin, extracts the Bash command,
/// and emits a rewrite directive if ztk has a filter for it. Otherwise
/// emits nothing (passthrough).
///
/// ztk is a compression tool, not a security tool. Permission checking
/// is Claude Code's job (via settings.permissions). The earlier version
/// of this hook tried to do both and blocked legitimate commands like
/// `git commit -m "multi\nline"` because multi-line strings contain
/// newlines. Defense in depth was the wrong design — it caused false
/// positives that broke normal dev workflows.
///
/// Claude Code's PreToolUse hook protocol: the hook should ALWAYS exit 0
/// and communicate its decision via JSON on stdout. Format:
///
///   {"hookSpecificOutput": {"hookEventName": "PreToolUse",
///    "permissionDecision": "allow",
///    "updatedInput": {"command": "ztk run <original>"}}}
///
/// No output (empty stdout) means "no opinion, let Claude Code decide".
pub fn runRewrite(allocator: std.mem.Allocator) !u8 {
    const stdin_bytes = readStdin(allocator) catch return 0;
    defer allocator.free(stdin_bytes);

    // Debug: record every invocation so we can verify Claude Code is calling us
    debugLog("called", stdin_bytes) catch {};

    const command = extractCommand(allocator, stdin_bytes) catch {
        debugLog("parse-fail", stdin_bytes) catch {};
        return 0;
    };
    defer allocator.free(command);
    if (command.len == 0) {
        debugLog("empty-cmd", "") catch {};
        return 0;
    }

    if (!hasFilterFor(command)) {
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
    const path = try std.fmt.bufPrint(&buf, "{s}/.local/share/ztk/hook-debug.log", .{home});
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

/// Parse the Claude Code PreToolUse payload and return a dup'd copy of
/// `tool_input.command`. Caller frees with the provided allocator.
pub fn extractCommand(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.MissingField;
    const tool_input = root.object.get("tool_input") orelse return error.MissingField;
    if (tool_input != .object) return error.MissingField;
    const cmd = tool_input.object.get("command") orelse return error.MissingField;
    if (cmd != .string) return error.MissingField;
    return allocator.dupe(u8, cmd.string);
}

/// Returns true if any registered comptime filter's command is a
/// whitespace-delimited prefix of `command`.
pub fn hasFilterFor(command: []const u8) bool {
    for (comptime_filters.spec_names) |name| {
        if (!std.mem.startsWith(u8, command, name)) continue;
        if (command.len == name.len) return true;
        const next = command[name.len];
        if (next == ' ' or next == '\t') return true;
    }
    return false;
}

fn emitRewrite(allocator: std.mem.Allocator, command: []const u8) !void {
    // Claude Code PreToolUse hook JSON format.
    // permissionDecision="ask" + updatedInput triggers the rewrite flow.
    const rewritten = try std.fmt.allocPrint(allocator, "ztk run {s}", .{command});
    defer allocator.free(rewritten);
    const escaped = try jsonEscape(allocator, rewritten);
    defer allocator.free(escaped);
    var buf: [8192]u8 = undefined;
    const payload = try std.fmt.bufPrint(
        &buf,
        "{{\"hookSpecificOutput\":{{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"ztk auto-rewrite for token savings\",\"updatedInput\":{{\"command\":\"{s}\"}}}}}}\n",
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

test "extractCommand parses tool_input.command" {
    const allocator = std.testing.allocator;
    const sample =
        \\{"tool_name":"Bash","tool_input":{"command":"git status -s","description":"x"}}
    ;
    const cmd = try extractCommand(allocator, sample);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("git status -s", cmd);
}

test "extractCommand fails on missing field" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingField, extractCommand(allocator, "{}"));
}

test "hasFilterFor detects known command prefix" {
    try std.testing.expect(hasFilterFor("git status"));
    try std.testing.expect(hasFilterFor("git status -s"));
    try std.testing.expect(!hasFilterFor("git statusfoo"));
    try std.testing.expect(!hasFilterFor("unknown_tool"));
}

test "jsonEscape handles quotes and backslashes" {
    const allocator = std.testing.allocator;
    const out = try jsonEscape(allocator, "cmd \"arg\"\n\\");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("cmd \\\"arg\\\"\\n\\\\", out);
}
