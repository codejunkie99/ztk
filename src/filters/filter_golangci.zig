const std = @import("std");
const compat = @import("../compat.zig");
const lint = @import("lint.zig");

const Issue = struct {
    linter: []const u8,
    text: []const u8,
    file: []const u8,
    line: i64,
};

pub fn filterGolangci(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "golangci-lint: ok");
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '{') {
        return filterJson(trimmed, allocator) catch {
            return lint.filterLint(input, allocator);
        };
    }
    return lint.filterLint(input, allocator);
}

fn filterJson(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return allocator.dupe(u8, input);
    const issues_value = root.object.get("Issues") orelse return allocator.dupe(u8, "golangci-lint: ok");
    if (issues_value != .array or issues_value.array.items.len == 0) return allocator.dupe(u8, "golangci-lint: ok");

    var issues: std.ArrayList(Issue) = .empty;
    defer issues.deinit(allocator);
    for (issues_value.array.items) |item| {
        if (item != .object) continue;
        const pos = item.object.get("Pos") orelse continue;
        if (pos != .object) continue;
        try issues.append(allocator, .{
            .linter = jsonString(item.object.get("FromLinter")) orelse "unknown",
            .text = jsonString(item.object.get("Text")) orelse "",
            .file = jsonString(pos.object.get("Filename")) orelse "",
            .line = jsonInt(pos.object.get("Line")) orelse 0,
        });
    }
    if (issues.items.len == 0) return allocator.dupe(u8, "golangci-lint: ok");

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.print("golangci-lint: {d} issues in {d} files\n", .{ issues.items.len, countFiles(issues.items) });
    try writeLinters(w, issues.items);
    for (issues.items) |issue| {
        if (issue.line > 0) {
            try w.print("{s}:{d} {s}: {s}\n", .{ issue.file, issue.line, issue.linter, issue.text });
        } else {
            try w.print("{s} {s}: {s}\n", .{ issue.file, issue.linter, issue.text });
        }
    }
    return out.toOwnedSlice(allocator);
}

fn jsonString(v: ?std.json.Value) ?[]const u8 {
    const value = v orelse return null;
    return if (value == .string) value.string else null;
}

fn jsonInt(v: ?std.json.Value) ?i64 {
    const value = v orelse return null;
    return switch (value) {
        .integer => |i| i,
        else => null,
    };
}

fn countFiles(issues: []const Issue) usize {
    var count: usize = 0;
    for (issues, 0..) |issue, i| {
        var seen = false;
        for (issues[0..i]) |prev| {
            if (std.mem.eql(u8, prev.file, issue.file)) {
                seen = true;
                break;
            }
        }
        if (!seen) count += 1;
    }
    return count;
}

fn writeLinters(w: anytype, issues: []const Issue) error{OutOfMemory}!void {
    try w.writeAll("linters: ");
    for (issues, 0..) |issue, i| {
        var seen = false;
        for (issues[0..i]) |prev| {
            if (std.mem.eql(u8, prev.linter, issue.linter)) {
                seen = true;
                break;
            }
        }
        if (seen) continue;
        var count: usize = 1;
        for (issues[i + 1 ..]) |next| {
            if (std.mem.eql(u8, next.linter, issue.linter)) count += 1;
        }
        if (i != 0) try w.writeAll(", ");
        try w.print("{s}: {d}", .{ issue.linter, count });
    }
    try w.writeByte('\n');
}

test "golangci json groups by linter and keeps issue text" {
    const input =
        \\{"Issues":[{"FromLinter":"revive","Text":"exported function Run should have comment","Pos":{"Filename":"cmd/app/main.go","Line":8,"Column":1},"SourceLines":["func Run() {}"]},{"FromLinter":"ineffassign","Text":"ineffectual assignment to err","Pos":{"Filename":"pkg/api/api.go","Line":12,"Column":2},"SourceLines":["err := call()"]}]}
    ;
    const r = try filterGolangci(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "golangci-lint: 2 issues in 2 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "revive: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "cmd/app/main.go:8 revive") != null);
}
