//! Subcommand dispatcher for the ztk CLI. Routes argv to handlers
//! and returns an exit code. No filter/exec logic lives here — that
//! belongs in proxy.zig and the hooks/ modules.

const std = @import("std");
const proxy = @import("proxy.zig");
const claude = @import("hooks/claude.zig");
const filter_cmd = @import("filter_cmd.zig");
const stats = @import("stats.zig");
const compat = @import("compat.zig");

const version_str = "ztk 0.2.1";

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
    if (eq(sub, "rewrite")) return claude.runRewrite(allocator);
    if (eq(sub, "run")) {
        if (args.len < 3) {
            try compat.writeStderr("usage: ztk run <cmd> [args...]\n");
            return 1;
        }
        return proxy.runProxy(args[2..], allocator);
    }
    if (eq(sub, "filter")) return filter_cmd.run(args, allocator);
    if (eq(sub, "stats")) return stats.run(allocator);

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "ztk: unknown command: {s}\n", .{sub}) catch "ztk: unknown command\n";
    compat.writeStderr(msg) catch {};
    try usage();
    return 1;
}

fn runInitCmd(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    var global = false;
    for (args[2..]) |a| {
        if (eq(a, "-g") or eq(a, "--global")) global = true;
    }
    try claude.runInit(allocator, global);
    return 0;
}

fn usage() !void {
    try compat.writeStderr(
        \\usage: ztk <command> [args...]
        \\
        \\commands:
        \\  run <cmd> [args...]   execute command and emit compact output
        \\  init [-g]             install Claude Code PreToolUse hook
        \\  rewrite               PreToolUse hook handler (reads stdin)
        \\  stats                 print savings stats
        \\  version               print version
        \\
    );
}

inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "version constant" {
    try std.testing.expectEqualStrings("ztk 0.2.1", version_str);
}

test "run with no args returns 1" {
    const code = try run(&.{"ztk"}, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), code);
}
