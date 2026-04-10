//! `ztk filter <name>` subcommand: read all of stdin, run it through the
//! comptime filter dispatcher with the given command name, and write the
//! filtered output to stdout. Used for benchmarking filters against fixture
//! inputs without having to re-execute the underlying commands.

const std = @import("std");
const comptime_filters = @import("filters/comptime.zig");

/// Reads stdin, dispatches to the named filter, writes filtered output to
/// stdout. Returns 0 on a filter match, 1 if no filter matched the name or
/// if usage was wrong.
pub fn run(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    if (args.len < 3) {
        try std.fs.File.stderr().writeAll("usage: ztk filter <name>\n");
        return 1;
    }
    const name = args[2];

    const stdin_bytes = try readAllStdin(allocator);

    if (comptime_filters.dispatch(name, stdin_bytes, allocator)) |fr| {
        try std.fs.File.stdout().writeAll(fr.output);
        return 0;
    }
    try std.fs.File.stderr().writeAll("ztk filter: no filter matched\n");
    return 1;
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    const stdin = std.fs.File.stdin();
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;
        try list.appendSlice(allocator, buf[0..n]);
    }
    return list.toOwnedSlice(allocator);
}
