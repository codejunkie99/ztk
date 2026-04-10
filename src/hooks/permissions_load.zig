const std = @import("std");

pub const Rules = struct {
    deny: []const []const u8,
    ask: []const []const u8,
};

pub const LoadError = error{ MalformedSettings, OutOfMemory };

/// Load deny/ask rules. Fail-closed on ambiguity: FileNotFound skips
/// silently (per-project files are optional); other open/read errors
/// inject a deny-all ("*") entry; malformed JSON returns
/// error.MalformedSettings (caller maps to `.ask`). Caller owns slices.
pub fn loadRules(
    settings_paths: []const []const u8,
    allocator: std.mem.Allocator,
) LoadError!Rules {
    var deny: std.ArrayList([]const u8) = .{};
    var ask: std.ArrayList([]const u8) = .{};

    for (settings_paths) |path| {
        const bytes = readFileBytes(path, allocator) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {
                warn("ztk: warning: could not read settings file '{s}' ({s}); failing closed\n", .{ path, @errorName(err) });
                try deny.append(allocator, try allocator.dupe(u8, "*"));
                continue;
            },
        };
        defer allocator.free(bytes);
        appendFromJson(bytes, &deny, &ask, allocator) catch |err| {
            warn("ztk: warning: malformed settings JSON in '{s}' ({s})\n", .{ path, @errorName(err) });
            return error.MalformedSettings;
        };
    }

    return .{
        .deny = try deny.toOwnedSlice(allocator),
        .ask = try ask.toOwnedSlice(allocator),
    };
}

fn warn(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.fs.File.stderr().writeAll(msg) catch {};
}

fn readFileBytes(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1 << 20);
}

fn appendFromJson(
    bytes: []const u8,
    deny: *std.ArrayList([]const u8),
    ask: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.MalformedSettings;
    const perms = root.object.get("permissions") orelse return;
    if (perms != .object) return error.MalformedSettings;
    if (perms.object.get("deny")) |v| try collectBash(v, deny, allocator);
    if (perms.object.get("ask")) |v| try collectBash(v, ask, allocator);
}

fn collectBash(
    value: std.json.Value,
    out: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    if (value != .array) return;
    for (value.array.items) |item| {
        if (item != .string) continue;
        const inner = stripBash(item.string) orelse continue;
        try out.append(allocator, try allocator.dupe(u8, inner));
    }
}

fn stripBash(s: []const u8) ?[]const u8 {
    const prefix = "Bash(";
    if (s.len < prefix.len + 1) return null;
    if (!std.mem.startsWith(u8, s, prefix)) return null;
    if (s[s.len - 1] != ')') return null;
    return s[prefix.len .. s.len - 1];
}

test "stripBash extracts inner pattern" {
    try std.testing.expectEqualStrings("git push*", stripBash("Bash(git push*)").?);
    try std.testing.expect(stripBash("Read(*)") == null);
    try std.testing.expect(stripBash("Bash") == null);
}
