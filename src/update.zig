const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");
const executor = @import("executor.zig");
const version = @import("version.zig");

const latest_release_url = "https://api.github.com/repos/codejunkie99/ztk/releases/latest";

const Options = struct {
    check: bool = false,
    dry_run: bool = false,
    help: bool = false,
    tag: ?[]const u8 = null,
};

pub fn run(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    const opts = parseOptions(args[2..]) catch {
        try usage();
        return 1;
    };
    if (opts.help) {
        try usage();
        return 0;
    }

    const latest_tag = if (opts.tag) |tag|
        tag
    else
        try fetchLatestTag(allocator);
    defer if (opts.tag == null) allocator.free(latest_tag);

    if (isCurrentLatest(version.value, latest_tag)) {
        try compat.writeStdout("ztk is already up to date (" ++ version.display ++ ")\n");
        return 0;
    }

    var msg: [128]u8 = undefined;
    const update_msg = try std.fmt.bufPrint(&msg, "ztk {s} -> {s}\n", .{ version.value, latest_tag });
    try compat.writeStdout(update_msg);
    if (opts.check) return 0;

    if (builtin.os.tag == .windows) {
        try compat.writeStderr("ztk update is not supported on Windows yet. Install the latest release manually.\n");
        return 1;
    }

    const exe_path = try std.process.executablePathAlloc(compat.io(), allocator);
    defer allocator.free(exe_path);

    if (isHomebrewManagedPath(exe_path)) {
        try compat.writeStderr("ztk update will not overwrite a Homebrew-managed install.\nRun: brew upgrade codejunkie99/ztk/ztk\n");
        return 1;
    }

    const script = try buildUpdateScript(allocator, exe_path, latest_tag);
    defer allocator.free(script);

    if (opts.dry_run) {
        try compat.writeStdout(script);
        return 0;
    }

    try compat.writeStdout("downloading and rebuilding latest ztk release...\n");
    const result = try executor.exec(&.{ "sh", "-c", script }, allocator, .filter_both);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) try compat.writeStdout(result.stdout);
    if (result.stderr.len > 0) try compat.writeStderr(result.stderr);
    if (result.exit_code != 0) {
        try compat.writeStderr("ztk update failed\n");
        return result.exit_code;
    }

    return 0;
}

fn parseOptions(args: []const []const u8) !Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--check")) {
            opts.check = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            opts.dry_run = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            opts.help = true;
        } else if (std.mem.eql(u8, arg, "--tag")) {
            i += 1;
            if (i >= args.len) return error.MissingTag;
            opts.tag = args[i];
        } else {
            return error.UnknownOption;
        }
    }
    return opts;
}

fn usage() !void {
    try compat.writeStderr(
        \\usage: ztk update [--check] [--dry-run] [--tag vX.Y.Z]
        \\
        \\downloads the latest GitHub release source, builds it with Zig,
        \\and installs it over the current non-Homebrew ztk executable.
        \\
    );
}

fn fetchLatestTag(allocator: std.mem.Allocator) ![]const u8 {
    const result = try executor.exec(&.{ "curl", "-fsSL", latest_release_url }, allocator, .filter_stdout_only);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.exit_code != 0) {
        if (result.stderr.len > 0) try compat.writeStderr(result.stderr);
        return error.UpdateCheckFailed;
    }

    const tag = try parseLatestTag(result.stdout);
    return try allocator.dupe(u8, tag);
}

fn parseLatestTag(json: []const u8) ![]const u8 {
    const key = "\"tag_name\"";
    const key_pos = std.mem.indexOf(u8, json, key) orelse return error.MissingTagName;
    const after_key = json[key_pos + key.len ..];
    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return error.MissingTagName;
    const after_colon = trimJsonWhitespaceLeft(after_key[colon_pos + 1 ..]);
    if (after_colon.len == 0 or after_colon[0] != '"') return error.MissingTagName;

    var end: usize = 1;
    while (end < after_colon.len and after_colon[end] != '"') : (end += 1) {}
    if (end >= after_colon.len) return error.MissingTagName;
    return after_colon[1..end];
}

fn trimJsonWhitespaceLeft(bytes: []const u8) []const u8 {
    var i: usize = 0;
    while (i < bytes.len and switch (bytes[i]) {
        ' ', '\t', '\r', '\n' => true,
        else => false,
    }) : (i += 1) {}
    return bytes[i..];
}

fn isCurrentLatest(current: []const u8, latest_tag: []const u8) bool {
    const latest = if (std.mem.startsWith(u8, latest_tag, "v")) latest_tag[1..] else latest_tag;
    return std.mem.eql(u8, current, latest);
}

fn isHomebrewManagedPath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "/Cellar/") != null or
        std.mem.startsWith(u8, path, "/opt/homebrew/") or
        std.mem.startsWith(u8, path, "/usr/local/Homebrew/");
}

fn buildUpdateScript(allocator: std.mem.Allocator, target_path: []const u8, tag: []const u8) ![]const u8 {
    const version_dir = if (std.mem.startsWith(u8, tag, "v")) tag[1..] else tag;
    const target = try shellQuote(allocator, target_path);
    defer allocator.free(target);

    const tarball_url = try std.fmt.allocPrint(allocator, "https://github.com/codejunkie99/ztk/archive/refs/tags/{s}.tar.gz", .{tag});
    defer allocator.free(tarball_url);
    const tarball = try shellQuote(allocator, tarball_url);
    defer allocator.free(tarball);

    return try std.fmt.allocPrint(allocator,
        \\set -eu
        \\tmp=$(mktemp -d "${{TMPDIR:-/tmp}}/ztk-update.XXXXXX")
        \\cleanup() {{ rm -rf "$tmp"; }}
        \\trap cleanup EXIT
        \\curl -fsSL -o "$tmp/ztk.tar.gz" {s}
        \\tar -xzf "$tmp/ztk.tar.gz" -C "$tmp"
        \\cd "$tmp/ztk-{s}"
        \\zig build -Doptimize=ReleaseSmall
        \\target={s}
        \\new_target="${{target}}.new.$$"
        \\install -m 755 zig-out/bin/ztk "$new_target"
        \\mv "$new_target" "$target"
        \\"$target" --version
        \\
    , .{ tarball, version_dir, target });
}

fn shellQuote(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.append(allocator, '\'');
    for (value) |byte| {
        if (byte == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, byte);
        }
    }
    try out.append(allocator, '\'');
    return try out.toOwnedSlice(allocator);
}

test "parseLatestTag extracts tag_name from GitHub release JSON" {
    const json =
        \\{"url":"https://api.github.com/repos/codejunkie99/ztk/releases/1","tag_name":"v0.2.3","name":"ztk v0.2.3"}
    ;

    const tag = try parseLatestTag(json);

    try std.testing.expectEqualStrings("v0.2.3", tag);
}

test "isCurrentLatest compares current version to latest release tag" {
    try std.testing.expect(isCurrentLatest("0.2.2", "v0.2.2"));
    try std.testing.expect(!isCurrentLatest("0.2.2", "v0.2.3"));
}

test "shellQuote handles single quotes" {
    const quoted = try shellQuote(std.testing.allocator, "/tmp/ztk user's/bin/ztk");
    defer std.testing.allocator.free(quoted);

    try std.testing.expectEqualStrings("'/tmp/ztk user'\\''s/bin/ztk'", quoted);
}

test "buildUpdateScript downloads release tarball and installs target binary" {
    const script = try buildUpdateScript(std.testing.allocator, "/Users/me/.local/bin/ztk", "v0.2.3");
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "https://github.com/codejunkie99/ztk/archive/refs/tags/v0.2.3.tar.gz") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "cd \"$tmp/ztk-0.2.3\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "target='/Users/me/.local/bin/ztk'") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "mv \"$new_target\" \"$target\"") != null);
}
