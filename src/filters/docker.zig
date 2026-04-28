const std = @import("std");
const compat = @import("../compat.zig");

/// Docker output filter handling `docker ps`, `docker images`, and
/// `docker logs`. Each subcommand has a different compression strategy:
/// ps/images compress the table, logs dedup repeated lines.
pub fn filterDocker(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    // Auto-detect subcommand from output shape
    if (std.mem.indexOf(u8, input, "CONTAINER ID") != null) return compressPs(input, allocator);
    if (std.mem.indexOf(u8, input, "IMAGE ID") != null) return compressImages(input, allocator);
    // Default: treat as logs, dedup
    return dedupLogs(input, allocator);
}

fn compressPs(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "CONTAINER ID") != null) continue;
        // Extract NAME (last field) and IMAGE (2nd field) only
        var sp = std.mem.tokenizeAny(u8, line, "\t");
        var fields: [10][]const u8 = undefined;
        var n: usize = 0;
        while (sp.next()) |f| {
            if (n == 10) break;
            fields[n] = f;
            n += 1;
        }
        if (n >= 2) {
            const name = fields[n - 1];
            const image = fields[1];
            try w.print("{s} ({s})\n", .{ name, image });
            count += 1;
            if (count >= 20) break;
        }
    }
    if (count == 0) return allocator.dupe(u8, "docker ps: no containers");
    return out.toOwnedSlice(allocator);
}

fn compressImages(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "IMAGE ID") != null) continue;
        var sp = std.mem.tokenizeAny(u8, line, " \t");
        const repo = sp.next() orelse continue;
        const tag = sp.next() orelse "latest";
        try w.print("{s}:{s}\n", .{ repo, tag });
        count += 1;
        if (count >= 30) break;
    }
    if (count == 0) return allocator.dupe(u8, "docker images: none");
    return out.toOwnedSlice(allocator);
}

fn dedupLogs(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var prev: []const u8 = "";
    var dup_count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, prev)) {
            dup_count += 1;
            continue;
        }
        if (dup_count > 0) try w.print("  [x{d}]\n", .{dup_count + 1});
        try w.writeAll(line);
        try w.writeByte('\n');
        prev = line;
        dup_count = 0;
    }
    if (dup_count > 0) try w.print("  [x{d}]\n", .{dup_count + 1});
    return out.toOwnedSlice(allocator);
}

test "docker ps compresses table" {
    const input = "CONTAINER ID\tIMAGE\tCOMMAND\tSTATUS\tPORTS\tNAMES\nabc123\tnginx:latest\tentrypoint\tUp\t80\tweb1\n";
    const r = try filterDocker(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "web1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "nginx:latest") != null);
    try std.testing.expect(r.len < input.len);
}

test "docker logs dedupes repeats" {
    const input = "line A\nline B\nline B\nline B\nline C\n";
    const r = try filterDocker(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "x3") != null);
    try std.testing.expect(r.len < input.len);
}

test "docker empty" {
    const r = try filterDocker("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
