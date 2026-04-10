//! `ztk stats` — rich TUI dashboard showing token savings.
//! Colored output, efficiency meter, and per-command breakdown with impact bars.

const std = @import("std");
const render = @import("stats_render.zig");
const parse = @import("stats_parse.zig");

pub fn run(allocator: std.mem.Allocator) !u8 {
    const home = std.posix.getenv("HOME") orelse return 1;
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{s}/.local/share/ztk/savings.log", .{home});

    const bytes = std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try std.fs.File.stderr().writeAll("ztk: no savings log yet. Run some commands with `ztk run ...` first.\n");
            return 0;
        },
        else => return err,
    };
    defer allocator.free(bytes);

    var data = try parse.parseLog(bytes, allocator);
    defer data.deinit(allocator);

    try render.renderDashboard(&data, std.fs.File.stdout());
    return 0;
}
