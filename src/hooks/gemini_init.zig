const std = @import("std");
const gemini = @import("gemini.zig");
const buildSettings = @import("gemini_init_build.zig").buildSettings;
const compat = @import("../compat.zig");

/// Install the ztk BeforeTool hook into Gemini CLI's settings.json.
///
/// When `global` is true, writes to ~/.gemini/settings.json;
/// otherwise writes to .gemini/settings.json in the current directory.
pub fn runInit(allocator: std.mem.Allocator, global: bool) !void {
    const path = try resolveSettingsPath(allocator, global);
    defer allocator.free(path);
    const status = try writeInit(allocator, path);
    switch (status) {
        .already_installed => try compat.writeStdout("ztk Gemini CLI hook already installed\n"),
        .installed => {
            var buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "Installed ztk Gemini CLI hook in {s}\n", .{path});
            try compat.writeStdout(msg);
        },
    }
}

pub const InstallStatus = enum { installed, already_installed };

/// Ensure `settings_path` contains a BeforeTool hook that invokes
/// `ztk gemini-rewrite` for run_shell_command tool calls.
pub fn writeInit(allocator: std.mem.Allocator, settings_path: []const u8) !InstallStatus {
    if (std.fs.path.dirname(settings_path)) |dir| {
        compat.makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
    }
    const existing = readIfExists(allocator, settings_path) catch |e| return e;
    defer if (existing) |b| allocator.free(b);
    if (existing) |bytes| {
        if (std.mem.indexOf(u8, bytes, gemini.hook_command) != null) return .already_installed;
    }
    const merged = try buildSettings(allocator, existing);
    defer allocator.free(merged);
    try writeAtomic(settings_path, merged);
    return .installed;
}

fn resolveSettingsPath(allocator: std.mem.Allocator, global: bool) ![]u8 {
    if (global) {
        const home = try compat.getEnvOwned(allocator, "HOME");
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, gemini.gemini_dir, gemini.settings_filename });
    }
    return std.fs.path.join(allocator, &.{ gemini.gemini_dir, gemini.settings_filename });
}

fn readIfExists(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const f = compat.openFile(path, .{}) catch return null;
    defer compat.closeFile(f);
    const bytes = try compat.readFileToEndAlloc(f, allocator, 1 << 20);
    return bytes;
}

fn writeAtomic(path: []const u8, data: []const u8) !void {
    const f = try compat.createFile(path, .{
        .truncate = true,
        .permissions = compat.permissionsFromMode(0o644),
    });
    defer compat.closeFile(f);
    try compat.writeFileAll(f, data);
}
