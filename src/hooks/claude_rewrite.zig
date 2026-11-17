const std = @import("std");
const builtin = @import("builtin");
const comptime_filters = @import("../filters/comptime.zig");
const compat = @import("../compat.zig");
const permissions_shell = @import("permissions_shell.zig");

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
///
/// Flags (parsed from args[2..]):
///   --skip-permissions   emit "allow" instead of the default "ask".
///       Hook-emitted "ask" cannot be overridden by user permissions.allow
///       rules, so the default forces a prompt for every rewrite. With this
///       flag the rewrite is approved by the hook; user permissions.deny
///       and permissions.ask rules still fire on the rewritten command
///       (Claude Code always evaluates those regardless of hook decision).
pub fn runRewrite(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    var skip_permissions = false;
    if (args.len > 2) {
        for (args[2..]) |a| {
            if (std.mem.eql(u8, a, "--skip-permissions")) skip_permissions = true;
        }
    }

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

    if (!shouldRewrite(command)) {
        debugLog("passthrough", command) catch {};
        return 0;
    }

    debugLog("rewrite", command) catch {};
    try emitRewrite(allocator, command, skip_permissions);
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
    return comptime_filters.hasFilterForCommand(command);
}

/// Verbs that WRITE when they appear as the second token of a `gh <noun>`
/// invocation. The hook exists to compress read output; wrapping a mutation
/// routes its result through `ztk run`, which reports the wrapped form
/// instead of the real output and (before the stderr fix) swallowed gh's
/// error text entirely. The hook passes these through untouched.
const gh_mutating_verbs = [_][]const u8{
    "merge",    "create",  "edit",    "close",
    "reopen",   "delete",  "remove",  "ready",
    "lock",     "unlock",  "pin",     "unpin",
    "transfer", "comment", "approve", "promote",
    "deploy",   "archive", "restore", "import",
    "cancel",   "rerun",   "add",     "set",
};

fn isGhMutation(verb: []const u8) bool {
    for (gh_mutating_verbs) |v| {
        if (std.mem.eql(u8, verb, v)) return true;
    }
    // Prefixed gh verbs carry the same writes: add-assignee, remove-label,
    // set-default, and friends.
    return std.mem.startsWith(u8, verb, "add-") or
        std.mem.startsWith(u8, verb, "remove-") or
        std.mem.startsWith(u8, verb, "set-");
}

/// True when `command` writes through gh. `gh <noun> <verb>` is judged by
/// its verb; `gh api` only when it overrides the method to a write verb.
pub fn isMutatingCommand(command: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, command, " \t");
    const head = it.next() orelse return false;
    const head_base = if (std.mem.lastIndexOfScalar(u8, head, '/')) |i|
        head[i + 1 ..]
    else
        head;
    if (!std.mem.eql(u8, head_base, "gh")) return false;
    const noun = it.next() orelse return false;
    if (std.mem.eql(u8, noun, "api")) {
        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "-X") or std.mem.eql(u8, tok, "--method")) {
                const method = it.next() orelse return false;
                return std.mem.eql(u8, method, "POST") or
                    std.mem.eql(u8, method, "PUT") or
                    std.mem.eql(u8, method, "PATCH") or
                    std.mem.eql(u8, method, "DELETE");
            }
        }
        return false;
    }
    const verb = it.next() orelse return false;
    return isGhMutation(verb);
}

/// The hook's single rewrite gate: compress only read output of commands
/// ztk knows, and never touch commands whose shell content the harness
/// shell must judge itself. A command carrying backticks, `$()`, or
/// newlines inside a quoted argument (an `--body` value, a commit
/// message) is legitimate for the harness shell; wrapping it into
/// `ztk run` made the permission layer deny it and the real command
/// never ran.
pub fn shouldRewrite(command: []const u8) bool {
    if (!hasFilterFor(command)) return false;
    if (isMutatingCommand(command)) return false;
    if (permissions_shell.isSuspicious(command)) return false;
    return true;
}

fn emitRewrite(allocator: std.mem.Allocator, command: []const u8, skip_permissions: bool) !void {
    const payload = try buildRewritePayload(allocator, command, skip_permissions);
    defer allocator.free(payload);
    try compat.writeStdout(payload);
}

/// Build the PreToolUse hook JSON payload that rewrites `command` to
/// `ztk run <command>`. Decision is "allow" when `skip_permissions` is
/// true (auto-mode friendly), otherwise "ask" (forces a confirmation
/// prompt for every rewrite). Both forms still let Claude Code evaluate
/// permissions.deny and permissions.ask rules on the rewritten command.
pub fn buildRewritePayload(
    allocator: std.mem.Allocator,
    command: []const u8,
    skip_permissions: bool,
) ![]u8 {
    const decision: []const u8 = if (skip_permissions) "allow" else "ask";
    const rewritten = try std.fmt.allocPrint(allocator, "ztk run {s}", .{command});
    defer allocator.free(rewritten);
    const escaped = try jsonEscape(allocator, rewritten);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(
        allocator,
        "{{\"hookSpecificOutput\":{{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"{s}\",\"permissionDecisionReason\":\"ztk auto-rewrite for token savings\",\"updatedInput\":{{\"command\":\"{s}\"}}}}}}\n",
        .{ decision, escaped },
    );
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
    try std.testing.expect(hasFilterFor("/usr/bin/git status -s"));
    try std.testing.expect(hasFilterFor("rg reducer src"));
    try std.testing.expect(hasFilterFor("/opt/homebrew/bin/rg reducer src"));
    try std.testing.expect(hasFilterFor("jest --runInBand"));
    try std.testing.expect(hasFilterFor("pnpm test"));
    try std.testing.expect(hasFilterFor("mypy src"));
    try std.testing.expect(hasFilterFor("/bin/ls /tmp"));
    try std.testing.expect(hasFilterFor("/usr/bin/find . -type f"));
    try std.testing.expect(!hasFilterFor("git statusfoo"));
    try std.testing.expect(!hasFilterFor("unknown_tool"));
}

test "jsonEscape handles quotes and backslashes" {
    const allocator = std.testing.allocator;
    const out = try jsonEscape(allocator, "cmd \"arg\"\n\\");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("cmd \\\"arg\\\"\\n\\\\", out);
}

test "buildRewritePayload defaults to ask" {
    const allocator = std.testing.allocator;
    const out = try buildRewritePayload(allocator, "git status", false);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permissionDecision\":\"ask\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permissionDecision\":\"allow\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"command\":\"ztk run git status\"") != null);
}

test "buildRewritePayload with skip_permissions emits allow" {
    const allocator = std.testing.allocator;
    const out = try buildRewritePayload(allocator, "git status", true);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permissionDecision\":\"allow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permissionDecision\":\"ask\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"command\":\"ztk run git status\"") != null);
}

test "buildRewritePayload escapes embedded quotes in command" {
    const allocator = std.testing.allocator;
    const out = try buildRewritePayload(allocator, "git commit -m \"x\"", true);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk run git commit -m \\\"x\\\"") != null);
}
