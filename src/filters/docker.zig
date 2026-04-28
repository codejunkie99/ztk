const std = @import("std");
const compat = @import("../compat.zig");

/// Docker output filter handling `docker ps`, `docker images`, and
/// `docker logs`. Each subcommand has a different compression strategy:
/// ps/images compress the table, logs dedup repeated lines.
pub fn filterDocker(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    // Auto-detect subcommand from output shape
    if (std.mem.indexOf(u8, input, "CONTAINER ID") != null) return compressPs(input, allocator);
    if (std.mem.indexOf(u8, input, "SERVICE") != null and
        std.mem.indexOf(u8, input, "STATUS") != null)
        return compressComposePs(input, allocator);
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

fn compressComposePs(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "SERVICE") != null and
            std.mem.indexOf(u8, line, "STATUS") != null)
            continue;
        var sp = std.mem.tokenizeAny(u8, line, " \t");
        _ = sp.next() orelse continue; // NAME
        const image = sp.next() orelse continue;
        skipQuotedCommand(&sp);
        const service = sp.next() orelse continue;
        const status = findComposeStatus(line) orelse "unknown";
        try w.print("{s} {s} ({s})\n", .{ service, status, image });
        count += 1;
        if (count >= 30) {
            try w.writeAll("[+more services]\n");
            break;
        }
    }
    if (count == 0) return allocator.dupe(u8, "docker compose ps: no services");
    return out.toOwnedSlice(allocator);
}

fn skipQuotedCommand(sp: *std.mem.TokenIterator(u8, .any)) void {
    const first = sp.next() orelse return;
    if (first.len == 0 or first[0] != '"') return;
    if (first[first.len - 1] == '"' and first.len > 1) return;
    while (sp.next()) |part| {
        if (part.len > 0 and part[part.len - 1] == '"') return;
    }
}

fn findComposeStatus(line: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, line, "running") != null) return "running";
    if (std.mem.indexOf(u8, line, "exited") != null) return "exited";
    if (std.mem.indexOf(u8, line, "restarting") != null) return "restarting";
    if (std.mem.indexOf(u8, line, "paused") != null) return "paused";
    if (std.mem.indexOf(u8, line, "created") != null) return "created";
    return null;
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

test "docker compose ps compresses service table" {
    const input =
        \\NAME                IMAGE          COMMAND     SERVICE   CREATED          STATUS          PORTS
        \\api-1               app-api        "node"      api       2 minutes ago    running         3000/tcp
        \\db-1                postgres:16    "postgres"  db        2 minutes ago    exited (1)
    ;
    const r = try filterDocker(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "api running (app-api)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "db exited (postgres:16)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "COMMAND") == null);
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
