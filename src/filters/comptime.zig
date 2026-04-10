const std = @import("std");
const git_simple = @import("git_simple.zig");
const git_status = @import("git_status.zig");
const git_diff = @import("git_diff.zig");
const git_log = @import("git_log.zig");
const test_cargo = @import("test_cargo.zig");
const test_nextest = @import("test_nextest.zig");
const test_pytest = @import("test_pytest.zig");
const test_go = @import("test_go.zig");
const test_node = @import("test_node.zig");
const files_ls = @import("files_ls.zig");
const files_cat = @import("files_cat.zig");
const files_grep = @import("files_grep.zig");
const files_find = @import("files_find.zig");
const files_wc = @import("files_wc.zig");
const files_headtail = @import("files_headtail.zig");
const files_python = @import("files_python.zig");
const filter_build = @import("filter_build.zig");
const filter_zig = @import("filter_zig.zig");
const docker = @import("docker.zig");
const kubectl = @import("kubectl.zig");
const filter_curl = @import("filter_curl.zig");
const filter_tree = @import("filter_tree.zig");
const filter_json = @import("filter_json.zig");
const filter_gh = @import("filter_gh.zig");
const filter_log = @import("filter_log.zig");
const filter_env = @import("filter_env.zig");
const lint = @import("lint.zig");

pub const FilterFn = *const fn ([]const u8, std.mem.Allocator) error{OutOfMemory}![]const u8;

pub const CommandCategory = enum(u8) {
    fast_changing = 0, // git status, ls — 30s TTL
    medium = 1, // test runners — 2min TTL
    slow_changing = 2, // git log — 5min TTL
    immutable = 3, // git show <hash> — no TTL
    mutation = 4, // invalidates fast_changing
};

pub const FilterResult = struct {
    output: []const u8,
    stateful: bool,
    category: CommandCategory,
};

const Spec = struct {
    command: []const u8,
    filter: FilterFn,
    stateful: bool,
    category: CommandCategory,
};

const specs = [_]Spec{
    .{ .command = "git add", .filter = &git_simple.filterGitAdd, .stateful = false, .category = .mutation },
    .{ .command = "git commit", .filter = &git_simple.filterGitCommit, .stateful = false, .category = .mutation },
    .{ .command = "git push", .filter = &git_simple.filterGitPush, .stateful = false, .category = .mutation },
    .{ .command = "git status", .filter = &git_status.filterGitStatus, .stateful = true, .category = .fast_changing },
    .{ .command = "git diff", .filter = &git_diff.filterGitDiff, .stateful = true, .category = .fast_changing },
    .{ .command = "git log", .filter = &git_log.filterGitLog, .stateful = false, .category = .slow_changing },
    .{ .command = "cargo test", .filter = &test_cargo.filterCargoTest, .stateful = true, .category = .medium },
    .{ .command = "cargo nextest", .filter = &test_nextest.filterCargoNextest, .stateful = true, .category = .medium },
    .{ .command = "pytest", .filter = &test_pytest.filterPytest, .stateful = true, .category = .medium },
    .{ .command = "go test", .filter = &test_go.filterGoTest, .stateful = true, .category = .medium },
    .{ .command = "npm test", .filter = &test_node.filterNodeTest, .stateful = true, .category = .medium },
    .{ .command = "vitest", .filter = &test_node.filterNodeTest, .stateful = true, .category = .medium },
    .{ .command = "ls", .filter = &files_ls.filterLs, .stateful = false, .category = .fast_changing },
    .{ .command = "cat", .filter = &files_cat.filterCat, .stateful = false, .category = .immutable },
    .{ .command = "grep", .filter = &files_grep.filterGrep, .stateful = false, .category = .fast_changing },
    .{ .command = "find", .filter = &files_find.filterFind, .stateful = false, .category = .fast_changing },
    .{ .command = "cargo build", .filter = &filter_build.filterCargoBuild, .stateful = false, .category = .mutation },
    .{ .command = "tsc", .filter = &filter_build.filterTsc, .stateful = true, .category = .medium },
    .{ .command = "eslint", .filter = &lint.filterLint, .stateful = true, .category = .medium },
    .{ .command = "ruff", .filter = &lint.filterLint, .stateful = true, .category = .medium },
    .{ .command = "clippy", .filter = &lint.filterLint, .stateful = true, .category = .medium },
    .{ .command = "cargo clippy", .filter = &lint.filterLint, .stateful = true, .category = .medium },
    // Additional filters
    .{ .command = "wc", .filter = &files_wc.filterWc, .stateful = false, .category = .fast_changing },
    .{ .command = "tail", .filter = &files_headtail.filterHeadTail, .stateful = false, .category = .fast_changing },
    .{ .command = "head", .filter = &files_headtail.filterHeadTail, .stateful = false, .category = .fast_changing },
    .{ .command = "python3", .filter = &files_python.filterPython, .stateful = false, .category = .medium },
    .{ .command = "python", .filter = &files_python.filterPython, .stateful = false, .category = .medium },
    .{ .command = "zig", .filter = &filter_zig.filterZig, .stateful = false, .category = .medium },
    // Infrastructure filters
    .{ .command = "docker", .filter = &docker.filterDocker, .stateful = false, .category = .fast_changing },
    .{ .command = "kubectl", .filter = &kubectl.filterKubectl, .stateful = false, .category = .fast_changing },
    .{ .command = "curl", .filter = &filter_curl.filterCurl, .stateful = false, .category = .fast_changing },
    .{ .command = "tree", .filter = &filter_tree.filterTree, .stateful = false, .category = .fast_changing },
    .{ .command = "jq", .filter = &filter_json.filterJson, .stateful = false, .category = .fast_changing },
    .{ .command = "gh", .filter = &filter_gh.filterGh, .stateful = false, .category = .slow_changing },
    .{ .command = "tail -f", .filter = &filter_log.filterLog, .stateful = false, .category = .immutable },
    .{ .command = "env", .filter = &filter_env.filterEnv, .stateful = false, .category = .fast_changing },
};

comptime {
    @setEvalBranchQuota(40000);
    for (specs, 0..) |a, i| {
        for (specs[i + 1 ..]) |b| {
            if (std.hash.XxHash64.hash(0, a.command) == std.hash.XxHash64.hash(0, b.command)) {
                @compileError("hash collision between commands: " ++ a.command ++ " and " ++ b.command);
            }
        }
    }
}

/// Matches when `command` equals `spec` exactly OR when `command` starts with
/// `spec` followed by a space. This lets `git log -10` match the `git log` spec
/// while keeping `git logfoo` from matching.
fn commandMatches(command: []const u8, spec: []const u8) bool {
    if (command.len < spec.len) return false;
    if (!std.mem.eql(u8, command[0..spec.len], spec)) return false;
    return command.len == spec.len or command[spec.len] == ' ';
}

pub fn dispatch(command: []const u8, input: []const u8, alloc: std.mem.Allocator) ?FilterResult {
    // Try the longest spec first so `git status` beats `git` if both existed.
    // Specs are short and few, so a linear scan is fine.
    var best_idx: ?usize = null;
    var best_len: usize = 0;
    inline for (specs, 0..) |s, i| {
        if (commandMatches(command, s.command) and s.command.len > best_len) {
            best_idx = i;
            best_len = s.command.len;
        }
    }
    if (best_idx) |idx| {
        inline for (specs, 0..) |s, i| {
            if (i == idx) {
                const output = s.filter(input, alloc) catch return null;
                return .{ .output = output, .stateful = s.stateful, .category = s.category };
            }
        }
    }
    return null;
}

/// Names of all registered filter specs, for hook prefix lookups.
pub const spec_names: [specs.len][]const u8 = blk: {
    var names: [specs.len][]const u8 = undefined;
    for (specs, 0..) |s, i| names[i] = s.command;
    break :blk names;
};

test "dispatch returns null for unknown or empty command" {
    try std.testing.expect(dispatch("nonexistent_xyz", "", std.testing.allocator) == null);
    try std.testing.expect(dispatch("", "", std.testing.allocator) == null);
}
