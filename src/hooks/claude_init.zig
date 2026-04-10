const std = @import("std");
const claude = @import("claude.zig");
const buildSettings = @import("claude_init_build.zig").buildSettings;

/// Install the ztk PreToolUse hook into Claude Code's settings.
/// If `global` is true, target `$HOME/.claude/settings.json`;
/// otherwise target `./.claude/settings.json` in the current directory.
pub fn runInit(allocator: std.mem.Allocator, global: bool) !void {
    const path = try resolveSettingsPath(allocator, global);
    defer allocator.free(path);
    const status = try writeInit(allocator, path);
    const out = std.fs.File.stdout();
    switch (status) {
        .already_installed => try out.writeAll("ztk PreToolUse hook already installed\n"),
        .installed => {
            var buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "Installed ztk PreToolUse hook in {s}\n", .{path});
            try out.writeAll(msg);
        },
    }
}

pub const InstallStatus = enum { installed, already_installed };

/// Ensure `settings_path` contains a PreToolUse hook that invokes
/// `ztk rewrite` for Bash commands. Creates parent dirs and the file
/// if missing, merges into an existing object otherwise. Returns
/// `.already_installed` if a matching hook is already present.
pub fn writeInit(allocator: std.mem.Allocator, settings_path: []const u8) !InstallStatus {
    if (std.fs.path.dirname(settings_path)) |dir| {
        std.fs.cwd().makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
    }
    const existing = readIfExists(allocator, settings_path) catch |e| return e;
    defer if (existing) |b| allocator.free(b);
    if (existing) |bytes| {
        if (std.mem.indexOf(u8, bytes, claude.hook_command) != null) return .already_installed;
    }
    const merged = try buildSettings(allocator, existing);
    defer allocator.free(merged);
    try writeAtomic(settings_path, merged);
    return .installed;
}

fn resolveSettingsPath(allocator: std.mem.Allocator, global: bool) ![]u8 {
    if (global) {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.HomeNotSet;
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, claude.claude_dir, claude.settings_filename });
    }
    return std.fs.path.join(allocator, &.{ claude.claude_dir, claude.settings_filename });
}

fn readIfExists(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => return e,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, 1 << 20);
}

fn writeAtomic(path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true, .mode = 0o644 });
    defer file.close();
    try file.writeAll(bytes);
}

