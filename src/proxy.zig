const std = @import("std");
const builtin = @import("builtin");
const executor = @import("executor.zig");
const comptime_filters = @import("filters/comptime.zig");
const runtime_filters = @import("filters/runtime.zig");
const output = @import("output.zig");
const proxy_session = @import("proxy_session.zig");
const permissions = @import("hooks/permissions.zig");
const compat = @import("compat.zig");

pub fn runProxy(cmd_args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    const cmd_str = try std.mem.join(allocator, " ", cmd_args);
    defer allocator.free(cmd_str);
    if (!builtin.is_test) {
        if (try enforcePermissions(cmd_str, allocator)) |code| return code;
    }
    if (rawEnvEnabled(allocator)) return runCommandRaw(cmd_args, allocator);

    const result = try executor.exec(cmd_args, allocator, .filter_stdout_only);
    const processed = processOutput(cmd_str, &result, allocator);
    if (!builtin.is_test) {
        const log_path = resolveLogPath(allocator) catch null;
        defer if (log_path) |p| allocator.free(p);
        output.emitWithCommand(
            processed.stdout,
            .{
                .command = cmd_args[0],
                .original = result.stdout.len,
                .filtered = processed.stdout.len,
                .exit_code = result.exit_code,
            },
            log_path,
        ) catch {};
        if (processed.stderr.len > 0) compat.writeStderr(processed.stderr) catch {};
    }
    return result.exit_code;
}

pub fn runRaw(cmd_args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    const cmd_str = try std.mem.join(allocator, " ", cmd_args);
    defer allocator.free(cmd_str);
    if (!builtin.is_test) {
        if (try enforcePermissions(cmd_str, allocator)) |code| return code;
    }
    return runCommandRaw(cmd_args, allocator);
}

fn enforcePermissions(cmd_str: []const u8, allocator: std.mem.Allocator) !?u8 {
    const verdict = permissions.checkCommand(cmd_str, &.{}, allocator) catch .allow;
    switch (verdict) {
        .deny => {
            compat.writeStderr("ztk: command denied by permission rules\n") catch {};
            return 2;
        },
        .ask => {
            compat.writeStderr("ztk: command requires user confirmation\n") catch {};
            return 3;
        },
        .allow, .passthrough => {},
    }
    return null;
}

fn runCommandRaw(cmd_args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    const result = try executor.exec(cmd_args, allocator, .filter_stdout_only);
    if (result.stdout.len > 0) try compat.writeStdout(result.stdout);
    if (result.stderr.len > 0) try compat.writeStderr(result.stderr);
    return result.exit_code;
}

fn rawEnvEnabled(allocator: std.mem.Allocator) bool {
    const value = compat.getEnvOwned(allocator, "ZTK_RAW") catch return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes");
}

fn resolveLogPath(allocator: std.mem.Allocator) !?[]u8 {
    const env_key = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    const home = compat.getEnvOwned(allocator, env_key) catch |err| switch (err) {
        error.EnvironmentVariableMissing => return null,
        else => return err,
    };
    defer allocator.free(home);
    return try std.fmt.allocPrint(allocator, "{s}/.local/share/ztk/savings.log", .{home});
}

const FilteredOutput = struct {
    bytes: []const u8,
    stateful: bool,
    category: comptime_filters.CommandCategory,
    matched: bool,
};

const ProcessedOutput = struct {
    stdout: []const u8,
    stderr: []const u8,
};

fn processOutput(cmd: []const u8, result: *const executor.ExecResult, allocator: std.mem.Allocator) ProcessedOutput {
    // A command that FAILED must never be summarized as success. Filters
    // collapse empty input into "<cmd>: ok" / "<cmd>: no output" sentinels;
    // for a failed command whose diagnostics went to stderr (cargo build, go
    // build, ls, git status, ...) that sentinel is a false pass. Pass the
    // empty stdout through unchanged so the forwarded stderr is the whole
    // story. Commands that still produce stdout on failure are filtered
    // normally — their output carries the failure.
    if (result.exit_code != 0 and result.stdout.len == 0) {
        return .{ .stdout = result.stdout, .stderr = result.stderr };
    }
    const filtered = applyFilters(cmd, result.stdout, allocator);
    const final_bytes = maybeApplySession(cmd, filtered, allocator);
    return .{
        .stdout = final_bytes,
        .stderr = result.stderr,
    };
}

fn applyFilters(cmd: []const u8, stdout_bytes: []const u8, allocator: std.mem.Allocator) FilteredOutput {
    if (comptime_filters.dispatch(cmd, stdout_bytes, allocator)) |fr| {
        return .{ .bytes = fr.output, .stateful = fr.stateful, .category = fr.category, .matched = true };
    }
    if (runtime_filters.dispatch(cmd, stdout_bytes, allocator)) |maybe| {
        if (maybe) |buf| {
            return .{ .bytes = buf, .stateful = false, .category = .fast_changing, .matched = true };
        }
    } else |_| {}
    return .{ .bytes = stdout_bytes, .stateful = false, .category = .fast_changing, .matched = false };
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
    if (builtin.os.tag == .windows) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const code = try runProxy(&.{ "sh", "-c", "exit 42" }, arena.allocator());
    try std.testing.expectEqual(@as(u8, 42), code);
}

test "processOutput forwards stderr verbatim on nonzero exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const exec_result: executor.ExecResult = .{
        .stdout = "",
        .stderr = "ERROR: Coverage for branches (96.76%) does not meet global threshold (97%)\nerror: failed to push some refs to 'github.com:foo/bar.git'\n",
        .exit_code = 1,
    };
    const processed = processOutput("git push", &exec_result, arena.allocator());
    try std.testing.expectEqualStrings(exec_result.stderr, processed.stderr);
}

test "processOutput forwards stderr verbatim on zero exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const exec_result: executor.ExecResult = .{
        .stdout = "To github.com:user/repo\n   abc..def  main -> main\n",
        .stderr = "progress noise\n",
        .exit_code = 0,
    };
    const processed = processOutput("git push", &exec_result, arena.allocator());
    try std.testing.expectEqualStrings(exec_result.stderr, processed.stderr);
}

test "processOutput keeps stdout filter masking sensitive values on nonzero exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const exec_result: executor.ExecResult = .{
        .stdout = "API_KEY=topsecret\nPATH=/usr/bin\n",
        .stderr = "command failed\n",
        .exit_code = 1,
    };
    const processed = processOutput("env", &exec_result, arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, processed.stdout, "<masked>") != null);
    try std.testing.expect(std.mem.indexOf(u8, processed.stdout, "topsecret") == null);
    try std.testing.expectEqualStrings(exec_result.stderr, processed.stderr);
}

test "failed command with empty stdout is not summarized as ok" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const exec_result: executor.ExecResult = .{
        .stdout = "",
        .stderr = "error[E0425]: cannot find value `x`\n  --> src/main.rs:1:1\nerror: could not compile `z` (bin \"z\") due to 1 previous error\n",
        .exit_code = 101,
    };
    const processed = processOutput("cargo build", &exec_result, arena.allocator());
    // No synthesized "cargo build: ok"; stderr carries the failure.
    try std.testing.expectEqualStrings("", processed.stdout);
    try std.testing.expectEqualStrings(exec_result.stderr, processed.stderr);
}

test "successful command with empty stdout keeps ok summary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const exec_result: executor.ExecResult = .{
        .stdout = "",
        .stderr = "",
        .exit_code = 0,
    };
    const processed = processOutput("cargo build", &exec_result, arena.allocator());
    try std.testing.expectEqualStrings("cargo build: ok", processed.stdout);
}
