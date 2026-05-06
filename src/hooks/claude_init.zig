const std = @import("std");
const claude = @import("claude.zig");
const buildSettings = @import("claude_init_build.zig").buildSettings;
const compat = @import("../compat.zig");

/// Install the ztk PreToolUse hook into Claude Code's settings.
/// If `global` is true, target `$HOME/.claude/settings.json`;
/// otherwise target `./.claude/settings.json` in the current directory.
/// If `skip_permissions` is true, the hook command is written as
/// `ztk rewrite --skip-permissions` so the hook emits "allow" instead
/// of "ask" — auto-mode users aren't prompted on every rewrite, while
/// permissions.deny / .ask rules still apply to the rewritten command.
pub fn runInit(allocator: std.mem.Allocator, global: bool, skip_permissions: bool) !void {
    const path = try resolveSettingsPath(allocator, global);
    defer allocator.free(path);
    const status = try writeInit(allocator, path, skip_permissions);
    switch (status) {
        .already_installed => try compat.writeStdout("ztk PreToolUse hook already installed\n"),
        .installed => {
            var buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "Installed ztk PreToolUse hook in {s}\n", .{path});
            try compat.writeStdout(msg);
        },
        .conflict => {
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "ztk: an existing ztk PreToolUse hook in {s} uses different flags. Remove that entry and re-run.\n",
                .{path},
            ) catch "ztk: existing ztk hook uses different flags; remove it and re-run.\n";
            try compat.writeStderr(msg);
            return error.HookFlagMismatch;
        },
    }
}

pub const InstallStatus = enum { installed, already_installed, conflict };

/// Ensure `settings_path` contains a PreToolUse hook that invokes the
/// computed ztk rewrite command for Bash. Creates parent dirs and the
/// file if missing, merges into an existing object otherwise.
/// Returns `.already_installed` if the desired exact command is present,
/// `.conflict` if a different ztk-rewrite variant is present (refuses to
/// append a duplicate), and `.installed` after a fresh install or merge.
pub fn writeInit(
    allocator: std.mem.Allocator,
    settings_path: []const u8,
    skip_permissions: bool,
) !InstallStatus {
    if (std.fs.path.dirname(settings_path)) |dir| {
        compat.makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
    }
    const desired_cmd = if (skip_permissions) "ztk rewrite --skip-permissions" else "ztk rewrite";
    const existing = readIfExists(allocator, settings_path) catch |e| return e;
    defer if (existing) |b| allocator.free(b);
    if (existing) |bytes| {
        // Match the JSON-quoted command exactly so "ztk rewrite" doesn't
        // collide with "ztk rewrite --skip-permissions".
        var quoted_buf: [128]u8 = undefined;
        const quoted = std.fmt.bufPrint(&quoted_buf, "\"{s}\"", .{desired_cmd}) catch return error.OutOfMemory;
        if (std.mem.indexOf(u8, bytes, quoted) != null) return .already_installed;
        // Any other ztk rewrite variant present → conflict.
        if (std.mem.indexOf(u8, bytes, "\"ztk rewrite") != null) return .conflict;
    }
    const merged = try buildSettings(allocator, existing, desired_cmd);
    defer allocator.free(merged);
    try writeAtomic(settings_path, merged);
    return .installed;
}

fn resolveSettingsPath(allocator: std.mem.Allocator, global: bool) ![]u8 {
    if (global) {
        const home = compat.getEnvOwned(allocator, "HOME") catch return error.HomeNotSet;
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, claude.claude_dir, claude.settings_filename });
    }
    return std.fs.path.join(allocator, &.{ claude.claude_dir, claude.settings_filename });
}

fn readIfExists(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const file = compat.openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => return e,
    };
    defer compat.closeFile(file);
    return try compat.readFileToEndAlloc(file, allocator, 1 << 20);
}

fn writeAtomic(path: []const u8, bytes: []const u8) !void {
    const file = try compat.createFile(path, .{
        .truncate = true,
        .permissions = compat.permissionsFromMode(0o644),
    });
    defer compat.closeFile(file);
    try compat.writeFileAll(file, bytes);
}
