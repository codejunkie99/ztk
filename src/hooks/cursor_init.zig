const std = @import("std");
const cursor = @import("cursor.zig");
const compat = @import("../compat.zig");

pub fn runInit(allocator: std.mem.Allocator, global: bool) !void {
    const path = try resolveHooksPath(allocator, global);
    defer allocator.free(path);
    const status = try writeInit(allocator, path);
    switch (status) {
        .already_installed => try compat.writeStdout("ztk Cursor hook already installed\n"),
        .installed => {
            var buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "Installed ztk Cursor hook in {s}\n", .{path});
            try compat.writeStdout(msg);
        },
    }
}

pub const InstallStatus = enum { installed, already_installed };

pub fn writeInit(allocator: std.mem.Allocator, hooks_path: []const u8) !InstallStatus {
    if (std.fs.path.dirname(hooks_path)) |dir| {
        compat.makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
    }
    const existing = readIfExists(allocator, hooks_path) catch |e| return e;
    defer if (existing) |b| allocator.free(b);
    if (existing) |bytes| {
        if (std.mem.indexOf(u8, bytes, cursor.hook_command) != null) return .already_installed;
    }
    const merged = try buildHooksJson(allocator, existing);
    defer allocator.free(merged);
    try writeAtomic(hooks_path, merged);
    return .installed;
}

/// Build the serialized hooks.json contents. Cursor's format:
///
///   {"version": 1, "hooks": {"preToolUse": [...]}}
///
/// We merge our entry into an existing file's preToolUse array,
/// preserving any other events and version field.
fn buildHooksJson(allocator: std.mem.Allocator, existing: ?[]const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root = try loadOrInit(a, existing);
    try root.object.put(a, "version", .{ .integer = 1 });
    var hooks = try ensureObject(a, &root, "hooks");
    var pre = try ensureArray(a, hooks, "preToolUse");
    try pre.append(.{ .object = try buildEntry(a) });
    try hooks.put(a, "preToolUse", .{ .array = pre });

    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    std.json.Stringify.value(root, .{ .whitespace = .indent_2 }, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

fn buildEntry(a: std.mem.Allocator) !std.json.ObjectMap {
    var entry = try emptyObject(a);
    try entry.put(a, "matcher", .{ .string = cursor.hook_matcher });
    try entry.put(a, "command", .{ .string = cursor.hook_command });
    try entry.put(a, "type", .{ .string = "command" });
    return entry;
}

fn loadOrInit(a: std.mem.Allocator, existing: ?[]const u8) !std.json.Value {
    if (existing) |bytes| {
        if (std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{})) |v| {
            if (v == .object) return v;
        } else |_| {}
    }
    return .{ .object = try emptyObject(a) };
}

fn ensureObject(a: std.mem.Allocator, parent: *std.json.Value, key: []const u8) !*std.json.ObjectMap {
    if (parent.object.getPtr(key)) |p| {
        if (p.* == .object) return &p.object;
    }
    const empty = try emptyObject(a);
    try parent.object.put(a, key, .{ .object = empty });
    return &parent.object.getPtr(key).?.object;
}

fn ensureArray(a: std.mem.Allocator, parent: *std.json.ObjectMap, key: []const u8) !std.json.Array {
    if (parent.get(key)) |v| {
        if (v == .array) return v.array;
    }
    return std.json.Array.init(a);
}

fn emptyObject(a: std.mem.Allocator) !std.json.ObjectMap {
    return std.json.ObjectMap.init(a, &.{}, &.{});
}

fn resolveHooksPath(allocator: std.mem.Allocator, global: bool) ![]u8 {
    if (global) {
        const home = compat.getEnvOwned(allocator, "HOME") catch return error.HomeNotSet;
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, cursor.cursor_dir, cursor.hooks_filename });
    }
    return std.fs.path.join(allocator, &.{ cursor.cursor_dir, cursor.hooks_filename });
}

fn readIfExists(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const file = compat.openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => return e,
    };
    defer compat.closeFile(file);
    return try compat.readFileToEndAlloc(file, allocator, 1 << 20);
}

fn writeAtomic(path: []const u8, bytes: []const u8) !void {
    const file = try compat.createFile(path, .{
        .truncate = true,
        .permissions = compat.permissionsFromMode(0o644),
    });
    defer compat.closeFile(file);
    try compat.writeFileAll(file, bytes);
}

test "buildHooksJson creates fresh hooks.json" {
    const allocator = std.testing.allocator;
    const out = try buildHooksJson(allocator, null);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"preToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk cursor-rewrite") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"Shell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"version\"") != null);
}

test "buildHooksJson preserves existing hooks" {
    const allocator = std.testing.allocator;
    const prior =
        \\{"version":1,"hooks":{"preToolUse":[{"matcher":"Shell","command":"other-tool","type":"command"}]}}
    ;
    const out = try buildHooksJson(allocator, prior);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "other-tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk cursor-rewrite") != null);
}

test "buildHooksJson preserves other event types" {
    const allocator = std.testing.allocator;
    const prior =
        \\{"version":1,"hooks":{"postToolUse":[{"matcher":"Shell","command":"logger","type":"command"}]}}
    ;
    const out = try buildHooksJson(allocator, prior);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "postToolUse") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "logger") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk cursor-rewrite") != null);
}
