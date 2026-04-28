const std = @import("std");
const compat = @import("../compat.zig");

pub fn filterGoBuild(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "go build: ok");
    var errors: std.ArrayList([]const u8) = .empty;
    defer errors.deinit(allocator);

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (isErrorLine(line)) try errors.append(allocator, line);
    }

    if (errors.items.len == 0) return allocator.dupe(u8, "go build: ok");
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.print("go build: {d} errors\n", .{errors.items.len});
    const cap = @min(errors.items.len, 20);
    for (errors.items[0..cap]) |line| try w.print("  {s}\n", .{line});
    if (errors.items.len > cap) try w.print("+{d} more errors\n", .{errors.items.len - cap});
    return out.toOwnedSlice(allocator);
}

fn isErrorLine(line: []const u8) bool {
    if (line.len == 0) return false;
    const lower = std.ascii.allocLowerString(std.heap.page_allocator, line) catch return false;
    defer std.heap.page_allocator.free(lower);
    if (std.mem.startsWith(u8, lower, "go: downloading ") or
        std.mem.startsWith(u8, lower, "go: finding ") or
        std.mem.startsWith(u8, lower, "go: extracting ") or
        line[0] == '#') return false;
    if (std.mem.indexOf(u8, line, ".go:") != null) return true;
    if (std.mem.indexOf(u8, lower, "go.mod:") != null or
        std.mem.indexOf(u8, lower, "go.work:") != null or
        std.mem.indexOf(u8, lower, "go.sum:") != null) return true;
    const prefixes = [_][]const u8{
        "undefined: ",
        "cannot use ",
        "cannot find package ",
        "no required module provides package ",
        "missing go.sum entry for module providing package ",
        "found packages ",
        "go: go.mod file not found",
        "go: cannot load module ",
        "go: build failed",
        "go: error ",
        "error: ",
        "go: updates to go.mod needed",
        "go: inconsistent vendoring",
        "no go files in ",
    };
    for (prefixes) |prefix| if (std.mem.startsWith(u8, lower, prefix)) return true;
    return false;
}

test "go build keeps compiler errors and drops package headers" {
    const input =
        \\# app
        \\./cmd/app/main.go:10:2: undefined: missing
        \\./pkg/api/api.go:22:14: cannot use x as string value
    ;
    const r = try filterGoBuild(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "go build: 2 errors") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "undefined: missing") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "# app") == null);
}
