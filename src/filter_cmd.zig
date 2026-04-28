//! `ztk filter <name>` subcommand: read all of stdin, run it through the
//! comptime filter dispatcher with the given command name, and write the
//! filtered output to stdout. Used for benchmarking filters against fixture
//! inputs without having to re-execute the underlying commands.

const std = @import("std");
const comptime_filters = @import("filters/comptime.zig");
const compat = @import("compat.zig");

/// Reads stdin, dispatches to the named filter, writes filtered output to
/// stdout. Returns 0 on a filter match, 1 if no filter matched the name or
/// if usage was wrong.
pub fn run(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    if (args.len < 3) {
        try compat.writeStderr("usage: ztk filter <name>\n");
        return 1;
    }
    const name = args[2];

    const stdin_bytes = try readAllStdin(allocator);

    if (comptime_filters.dispatch(name, stdin_bytes, allocator)) |fr| {
        try compat.writeStdout(fr.output);
        return 0;
    }
    try compat.writeStderr("ztk filter: no filter matched\n");
    return 1;
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    return compat.readStdinAlloc(allocator, 16 * 1024 * 1024);
}
