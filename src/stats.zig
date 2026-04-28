//! `ztk stats` — rich TUI dashboard showing token savings.
//! Colored output, efficiency meter, and per-command breakdown with impact bars.

const std = @import("std");
const builtin = @import("builtin");
const render = @import("stats_render.zig");
const parse = @import("stats_parse.zig");
const compat = @import("compat.zig");

pub fn run(allocator: std.mem.Allocator) !u8 {
    const env_key = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    const home = compat.getEnvOwned(allocator, env_key) catch return 1;
    defer allocator.free(home);
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{s}/.local/share/ztk/savings.log", .{home});

    const bytes = compat.readFileAlloc(allocator, path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try compat.writeStderr("ztk: no savings log yet. Run some commands with `ztk run ...` first.\n");
            return 0;
        },
        else => return err,
    };
    defer allocator.free(bytes);

    var data = try parse.parseLog(bytes, allocator);
    defer data.deinit(allocator);

    try render.renderDashboard(&data, compat.stdoutWriter());
    return 0;
}
