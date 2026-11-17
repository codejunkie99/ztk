const std = @import("std");
const claude_init = @import("claude_init.zig");
const claude_rewrite = @import("claude_rewrite.zig");
const compat = @import("../compat.zig");

fn tmpRealPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![]u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(std.testing.io, ".", &buf);
    return allocator.dupe(u8, buf[0..len]);
}

test "runInit writes a fresh settings file into tmpdir" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    const status = try claude_init.writeInit(allocator, settings, false);
    try std.testing.expectEqual(claude_init.InstallStatus.installed, status);

    const file = try compat.openFile(settings, .{});
    defer compat.closeFile(file);
    const bytes = try compat.readFileToEndAlloc(file, allocator, 1 << 20);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"PreToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"ztk rewrite\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"Bash\"") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
}

test "runInit is idempotent when hook is already present" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    _ = try claude_init.writeInit(allocator, settings, false);
    const status2 = try claude_init.writeInit(allocator, settings, false);
    try std.testing.expectEqual(claude_init.InstallStatus.already_installed, status2);
}

test "runInit preserves unrelated top-level keys when merging" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    {
        const f = try compat.createFile(settings, .{ .truncate = true });
        defer compat.closeFile(f);
        try compat.writeFileAll(f, "{\"theme\":\"dark\"}");
    }
    _ = try claude_init.writeInit(allocator, settings, false);

    const f = try compat.openFile(settings, .{});
    defer compat.closeFile(f);
    const bytes = try compat.readFileToEndAlloc(f, allocator, 1 << 20);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"theme\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ztk rewrite") != null);
}

test "runInit with skip_permissions writes flagged hook command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    const status = try claude_init.writeInit(allocator, settings, true);
    try std.testing.expectEqual(claude_init.InstallStatus.installed, status);

    const f = try compat.openFile(settings, .{});
    defer compat.closeFile(f);
    const bytes = try compat.readFileToEndAlloc(f, allocator, 1 << 20);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"ztk rewrite --skip-permissions\"") != null);
}

test "runInit reports conflict when existing hook uses different flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    _ = try claude_init.writeInit(allocator, settings, false);
    const status2 = try claude_init.writeInit(allocator, settings, true);
    try std.testing.expectEqual(claude_init.InstallStatus.conflict, status2);
}

test "runInit idempotent on flagged re-install" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmpRealPath(allocator, &tmp);
    defer allocator.free(base);
    const settings = try std.fs.path.join(allocator, &.{ base, "settings.json" });
    defer allocator.free(settings);

    _ = try claude_init.writeInit(allocator, settings, true);
    const status2 = try claude_init.writeInit(allocator, settings, true);
    try std.testing.expectEqual(claude_init.InstallStatus.already_installed, status2);
}

test "sample Claude hook JSON yields expected command" {
    const allocator = std.testing.allocator;
    const payload =
        \\{"session_id":"abc","tool_name":"Bash","tool_input":{"command":"ls -la","description":"list"}}
    ;
    const cmd = try claude_rewrite.extractCommand(allocator, payload);
    defer allocator.free(cmd);
    try std.testing.expectEqualStrings("ls -la", cmd);
}

test "shouldRewrite passes mutations through unwrapped" {
    // The 2026-11-17 merge wave: every `gh pr merge` was rewritten into
    // `ztk run gh pr merge`, whose wrapper reported itself instead of the
    // merge result, and whose errors were invisible. Mutations must reach
    // the harness shell untouched.
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "gh pr merge 572 --repo okyeboah/agent-brain --squash --subject \"x\""));
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "gh issue comment 570 --repo okyeboah/agent-brain --body \"note\""));
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "gh pr create --title t --reviewers peer"));
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "gh api repos/o/r --method POST -f a=b"));
    // Reads stay compressible, including prefixed gh verbs that exist only
    // on one side of the mutation line.
    try std.testing.expect(claude_rewrite.shouldRewrite(
        "gh pr list --repo okyeboah/agent-brain --limit 5"));
    try std.testing.expect(claude_rewrite.shouldRewrite(
        "gh api repos/o/r/pulls/1 --jq .merged"));
}

test "isMutatingCommand judges the gh verb, not the flags" {
    try std.testing.expect(claude_rewrite.isMutatingCommand(
        "gh pr merge 1"));
    try std.testing.expect(claude_rewrite.isMutatingCommand(
        "/opt/homebrew/bin/gh issue edit 1 --title t"));
    try std.testing.expect(claude_rewrite.isMutatingCommand(
        "gh label add bug"));
    try std.testing.expect(!claude_rewrite.isMutatingCommand(
        "gh pr list --limit 5"));
    try std.testing.expect(!claude_rewrite.isMutatingCommand(
        "gh pr view 1 --json state"));
    try std.testing.expect(!claude_rewrite.isMutatingCommand("git push origin main"));
}

test "shouldRewrite never wraps shell-suspicious content" {
    // Backticks inside a quoted --body are argument text, not shell syntax
    // for the harness shell; wrapping made the permission layer deny the
    // command and the comment never posted.
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "gh issue comment 570 --body \"see `git rev-parse x` docs\""));
    try std.testing.expect(!claude_rewrite.shouldRewrite(
        "git commit -m \"multi\nline\""));
}
