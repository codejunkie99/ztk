//! Subcommand dispatcher for the ztk CLI. Routes argv to handlers
//! and returns an exit code. No filter/exec logic lives here — that
//! belongs in proxy.zig and the hooks/ modules.

const std = @import("std");
const proxy = @import("proxy.zig");
const claude = @import("hooks/claude.zig");
const cursor = @import("hooks/cursor.zig");
const gemini = @import("hooks/gemini.zig");
const filter_cmd = @import("filter_cmd.zig");
const stats = @import("stats.zig");
const update = @import("update.zig");
const compat = @import("compat.zig");
const version = @import("version.zig");

const version_str = version.display;

pub fn run(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    if (args.len < 2) {
        try usage();
        return 1;
    }
    const sub = args[1];

    if (eq(sub, "--version") or eq(sub, "version")) {
        try compat.writeStdout(version_str ++ "\n");
        return 0;
    }
    if (eq(sub, "init")) return runInitCmd(args, allocator);
    if (eq(sub, "rewrite")) return claude.runRewrite(args, allocator);
    if (eq(sub, "cursor-rewrite")) return cursor.runRewrite(allocator);
    if (eq(sub, "gemini-rewrite")) return gemini.runRewrite(allocator);
    if (eq(sub, "run")) {
        if (args.len < 3) {
            try compat.writeStderr("usage: ztk run <cmd> [args...]\n");
            return 1;
        }
        return proxy.runProxy(args[2..], allocator);
    }
    if (eq(sub, "filter")) return filter_cmd.run(args, allocator);
    if (eq(sub, "stats")) return stats.run(allocator);
    if (eq(sub, "update")) return update.run(args, allocator);

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "ztk: unknown command: {s}\n", .{sub}) catch "ztk: unknown command\n";
    compat.writeStderr(msg) catch {};
    try usage();
    return 1;
}

fn runInitCmd(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    var global = false;
    var skip_permissions = false;
    for (args[2..]) |a| {
        if (eq(a, "-g") or eq(a, "--global")) global = true;
        if (eq(a, "--skip-permissions")) skip_permissions = true;
    }
    var installed: u8 = 0;
    if (agentDirExists(allocator, global, claude.claude_dir)) {
        claude.runInit(allocator, global, skip_permissions) catch |err| switch (err) {
            error.HookFlagMismatch => return 1,
            else => return err,
        };
        installed += 1;
    }
    if (agentDirExists(allocator, global, cursor.cursor_dir)) {
        try cursor.runInit(allocator, global);
        installed += 1;
    }
    if (agentDirExists(allocator, global, gemini.gemini_dir)) {
        try gemini.runInit(allocator, global);
        installed += 1;
    }
    if (installed == 0) {
        try compat.writeStderr("ztk: no supported agent config directories found (.claude/, .cursor/, or .gemini/)\n");
        return 1;
    }
    return 0;
}

fn agentDirExists(allocator: std.mem.Allocator, global: bool, dir_name: []const u8) bool {
    if (global) {
        const home = compat.getEnvOwned(allocator, "HOME") catch return false;
        defer allocator.free(home);
        var buf: [512]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ home, dir_name }) catch return false;
        var d = compat.cwd().openDir(compat.io(), full, .{}) catch return false;
        d.close(compat.io());
        return true;
    }
    var d = compat.cwd().openDir(compat.io(), dir_name, .{}) catch return false;
    d.close(compat.io());
    return true;
}

fn usage() !void {
    try compat.writeStderr(
        \\usage: ztk <command> [args...]
        \\
        \\commands:
        \\  run <cmd> [args...]   execute command and emit compact output
        \\  init [-g] [--skip-permissions]
        \\                        install hooks for all supported agents
        \\                        (.claude/, .cursor/, .gemini/).
        \\                        -g writes to global config directories.
        \\                        --skip-permissions (Claude only) writes the
        \\                        hook as `ztk rewrite --skip-permissions`.
        \\  rewrite [--skip-permissions]
        \\                        Claude PreToolUse hook handler (reads stdin).
        \\                        --skip-permissions emits "allow" instead of
        \\                        "ask" so auto-mode users aren't prompted on
        \\                        every rewrite. permissions.deny / .ask rules
        \\                        still apply to the rewritten command.
        \\  cursor-rewrite        Cursor preToolUse hook handler (reads stdin)
        \\  gemini-rewrite        Gemini CLI BeforeTool hook handler (reads stdin)
        \\  stats                 print savings stats
        \\  update                update this ztk executable from GitHub
        \\  version               print version
        \\
    );
}

inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "version constant" {
    try std.testing.expectEqualStrings("ztk 0.2.3", version_str);
}

test "run with no args returns 1" {
    const code = try run(&.{"ztk"}, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), code);
}
