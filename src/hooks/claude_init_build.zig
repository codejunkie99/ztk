const std = @import("std");
const claude = @import("claude.zig");

/// Build the serialized settings.json contents that should replace any
/// existing file at the hook install path. `existing` is the prior file
/// bytes (or null) — if present and parseable, other top-level keys are
/// preserved and only the hooks.PreToolUse array is mutated.
pub fn buildSettings(allocator: std.mem.Allocator, existing: ?[]const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root = try loadOrInit(a, existing);
    var hooks = try ensureObject(a, &root, "hooks");
    var pre = try ensureArray(a, hooks, "PreToolUse");
    try pre.append(try buildEntry(a));
    try hooks.put(a, "PreToolUse", .{ .array = pre });

    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    std.json.Stringify.value(root, .{ .whitespace = .indent_2 }, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
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

fn buildEntry(a: std.mem.Allocator) !std.json.Value {
    var entry = try emptyObject(a);
    try entry.put(a, "matcher", .{ .string = claude.hook_matcher });

    var inner = try emptyObject(a);
    try inner.put(a, "type", .{ .string = "command" });
    try inner.put(a, "command", .{ .string = claude.hook_command });

    var hooks_arr = std.json.Array.init(a);
    try hooks_arr.append(.{ .object = inner });
    try entry.put(a, "hooks", .{ .array = hooks_arr });
    return .{ .object = entry };
}

fn emptyObject(a: std.mem.Allocator) !std.json.ObjectMap {
    return std.json.ObjectMap.init(a, &.{}, &.{});
}

test "buildSettings creates fresh JSON with hook" {
    const allocator = std.testing.allocator;
    const out = try buildSettings(allocator, null);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"PreToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk rewrite") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"Bash\"") != null);
}

test "buildSettings preserves existing top-level keys" {
    const allocator = std.testing.allocator;
    const prior = "{\"theme\":\"dark\",\"permissions\":{\"deny\":[\"Bash(rm -rf*)\"]}}";
    const out = try buildSettings(allocator, prior);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"theme\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permissions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk rewrite") != null);
}

test "buildSettings appends to existing PreToolUse array" {
    const allocator = std.testing.allocator;
    const prior = "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Edit\",\"hooks\":[]}]}}";
    const out = try buildSettings(allocator, prior);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"Edit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"Bash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ztk rewrite") != null);
}
