const std = @import("std");
const perms = @import("permissions.zig");
const matchPattern = @import("permissions_match.zig").matchPattern;

fn writeSettings(dir: *std.testing.TmpDir, name: []const u8, body: []const u8) ![]const u8 {
    var f = try dir.dir.createFile(name, .{});
    defer f.close();
    try f.writeAll(body);
    return dir.dir.realpathAlloc(std.testing.allocator, name);
}

test "allow when no rules match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const v = try perms.checkCommand("git status", &.{}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.allow, v);
}

test "deny rule blocks command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try writeSettings(&tmp, "settings.json",
        \\{"permissions":{"deny":["Bash(git push --force*)"]}}
    );
    defer std.testing.allocator.free(path);
    const v = try perms.checkCommand("git push --force", &.{path}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.deny, v);
}

test "ask rule prompts user" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try writeSettings(&tmp, "settings.json",
        \\{"permissions":{"ask":["Bash(npm publish*)"]}}
    );
    defer std.testing.allocator.free(path);
    const v = try perms.checkCommand("npm publish", &.{path}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.ask, v);
}

test "compound command denies on second segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try writeSettings(&tmp, "settings.json",
        \\{"permissions":{"deny":["Bash(git push --force*)"]}}
    );
    defer std.testing.allocator.free(path);
    const v = try perms.checkCommand("git add . && git push --force", &.{path}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.deny, v);
}

test "compound command without rules is allowed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const v = try perms.checkCommand("git add . && git commit", &.{}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.allow, v);
}

test "matchPattern prefix wildcard and miss" {
    try std.testing.expect(matchPattern("git push --force origin", "git push --force*"));
    try std.testing.expect(!matchPattern("git status", "git push --force*"));
}

test "missing settings file is fail-safe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const v = try perms.checkCommand("git status", &.{"/nonexistent/path/settings.json"}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.allow, v);
}

test "malformed settings file falls through to ask" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try writeSettings(&tmp, "settings.json", "{this is not: valid json");
    defer std.testing.allocator.free(path);
    const v = try perms.checkCommand("git status", &.{path}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.ask, v);
}

test "deny precedence over ask in compound command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try writeSettings(&tmp, "settings.json",
        \\{"permissions":{"deny":["Bash(rm -rf*)"],"ask":["Bash(npm publish*)"]}}
    );
    defer std.testing.allocator.free(path);
    const v = try perms.checkCommand("npm publish && rm -rf /", &.{path}, arena.allocator());
    try std.testing.expectEqual(perms.Verdict.deny, v);
}
