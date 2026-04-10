//! `ztk run` pipeline: execute the child command, route its stdout
//! through comptime then runtime filters, optionally consult the
//! session cache for a delta summary, emit the result, and propagate
//! the child's exit code. Filter and session failures are non-fatal —
//! the raw command output must always reach stdout.

const std = @import("std");
const builtin = @import("builtin");
const executor = @import("executor.zig");
const comptime_filters = @import("filters/comptime.zig");
const runtime_filters = @import("filters/runtime.zig");
const output = @import("output.zig");
const proxy_session = @import("proxy_session.zig");
const permissions = @import("hooks/permissions.zig");

pub fn runProxy(cmd_args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    const cmd_str = try std.mem.join(allocator, " ", cmd_args);

    // Permission check before exec. Same 4-exit-code protocol as the
    // rewrite hook: deny -> 2, ask -> 3, allow/passthrough -> continue.
    // During tests we skip the check to avoid reading real settings files.
    if (!builtin.is_test) {
        const verdict = permissions.checkCommand(cmd_str, &.{}, allocator) catch .allow;
        switch (verdict) {
            .deny => {
                std.fs.File.stderr().writeAll("ztk: command denied by permission rules\n") catch {};
                return 2;
            },
            .ask => {
                std.fs.File.stderr().writeAll("ztk: command requires user confirmation\n") catch {};
                return 3;
            },
            .allow, .passthrough => {},
        }
    }

    const result = try executor.exec(cmd_args, allocator, .filter_stdout_only);

    const filtered = applyFilters(cmd_str, result.stdout, allocator);
    const final_bytes = maybeApplySession(cmd_str, filtered, allocator);

    // Writing to stdout inside a Zig test corrupts the test runner's
    // IPC protocol (which speaks over stdin/stdout with --listen=-).
    if (!builtin.is_test) {
        const log_path = resolveLogPath(allocator) catch null;
        defer if (log_path) |p| allocator.free(p);
        const first_word = cmd_args[0];
        output.emitWithCommand(
            final_bytes,
            .{
                .command = first_word,
                .original = result.stdout.len,
                .filtered = final_bytes.len,
                .exit_code = result.exit_code,
            },
            log_path,
        ) catch {};
    }
    return result.exit_code;
}

fn resolveLogPath(allocator: std.mem.Allocator) !?[]u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    return try std.fmt.allocPrint(allocator, "{s}/.local/share/ztk/savings.log", .{home});
}

const FilteredOutput = struct {
    bytes: []const u8,
    stateful: bool,
    category: comptime_filters.CommandCategory,
    matched: bool,
};

fn applyFilters(cmd: []const u8, stdout_bytes: []const u8, allocator: std.mem.Allocator) FilteredOutput {
    if (comptime_filters.dispatch(cmd, stdout_bytes, allocator)) |fr| {
        return .{
            .bytes = fr.output,
            .stateful = fr.stateful,
            .category = fr.category,
            .matched = true,
        };
    }
    if (runtime_filters.dispatch(cmd, stdout_bytes, allocator)) |maybe| {
        if (maybe) |buf| {
            return .{
                .bytes = buf,
                .stateful = false,
                .category = .fast_changing,
                .matched = true,
            };
        }
    } else |_| {}
    return .{
        .bytes = stdout_bytes,
        .stateful = false,
        .category = .fast_changing,
        .matched = false,
    };
}

fn maybeApplySession(cmd: []const u8, f: FilteredOutput, allocator: std.mem.Allocator) []const u8 {
    if (!f.stateful or !f.matched) return f.bytes;
    return proxy_session.applySession(cmd, f.bytes, f.category, allocator) orelse f.bytes;
}

test "runProxy passthrough echo hello returns 0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try runProxy(&.{ "echo", "hello" }, arena.allocator());
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "runProxy preserves nonzero exit code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try runProxy(&.{ "sh", "-c", "exit 42" }, arena.allocator());
    try std.testing.expectEqual(@as(u8, 42), code);
}
