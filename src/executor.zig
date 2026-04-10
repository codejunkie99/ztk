const std = @import("std");

pub const StderrPolicy = enum {
    filter_stdout_only,
    filter_both,
    filter_stderr_only,
    merge_then_filter,
};

pub const ExecResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

// Per-stream cap. Bumped from 1 MiB → 16 MiB so most real-world commands
// (cargo builds, verbose test suites) stay under the limit. When a
// stream still exceeds this, `exec` catches the specific error and
// returns a sentinel ExecResult instead of bubbling the failure up to
// the proxy pipeline, so the user still sees a response.
const max_output = 16 * 1024 * 1024; // 16 MiB

const oversize_sentinel =
    "[ztk: command output exceeded 16MB cap, raw output suppressed]\n";

pub fn exec(
    argv: []const []const u8,
    allocator: std.mem.Allocator,
    policy: StderrPolicy,
) !ExecResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = max_output,
    }) catch |err| switch (err) {
        error.StdoutStreamTooLong, error.StderrStreamTooLong => return oversized(allocator),
        else => return err,
    };

    const exit_code: u8 = switch (result.term) {
        .Exited => |code| code,
        .Signal => |sig| @truncate(128 +% sig),
        .Stopped => |sig| @truncate(128 +% sig),
        .Unknown => 1,
    };

    // Apply stderr policy to decide what the caller filters as "stdout".
    // filter_stdout_only: default, unchanged
    // filter_stderr_only: swap streams so caller's filter runs on stderr
    // merge_then_filter: concatenate both onto stdout
    // filter_both: pass both through (caller filters each independently)
    return switch (policy) {
        .filter_stdout_only, .filter_both => .{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .exit_code = exit_code,
        },
        .filter_stderr_only => .{
            .stdout = result.stderr,
            .stderr = result.stdout,
            .exit_code = exit_code,
        },
        .merge_then_filter => blk: {
            const merged = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
            allocator.free(result.stdout);
            allocator.free(result.stderr);
            break :blk .{
                .stdout = merged,
                .stderr = try allocator.dupe(u8, ""),
                .exit_code = exit_code,
            };
        },
    };
}

fn oversized(allocator: std.mem.Allocator) !ExecResult {
    return .{
        .stdout = try allocator.dupe(u8, oversize_sentinel),
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

test {
    _ = @import("executor_test.zig");
}
