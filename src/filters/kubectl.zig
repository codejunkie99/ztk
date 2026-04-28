const std = @import("std");
const compat = @import("../compat.zig");

/// kubectl output filter. Auto-detects subcommand shape from the output:
///  - `kubectl get <resource>` produces a NAME/READY/STATUS table
///  - `kubectl logs <pod>` produces repeated log lines (dedup)
///  - `kubectl describe` produces sections and Events
pub fn filterKubectl(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    if (std.mem.indexOf(u8, input, "NAME ") != null and
        (std.mem.indexOf(u8, input, "READY") != null or
            std.mem.indexOf(u8, input, "STATUS") != null))
        return compressTable(input, allocator);
    if (std.mem.indexOf(u8, input, "Events:") != null) return compressDescribe(input, allocator);
    return dedupLogs(input, allocator);
}

fn compressTable(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "NAME ") or std.mem.startsWith(u8, line, "NAME\t")) continue;
        var sp = std.mem.tokenizeAny(u8, line, " \t");
        const name = sp.next() orelse continue;
        _ = sp.next(); // skip ready/desired
        const status = sp.next() orelse "";
        try w.print("{s} ({s})\n", .{ name, status });
        count += 1;
        if (count >= 30) break;
    }
    if (count == 0) return allocator.dupe(u8, "kubectl get: no resources");
    return out.toOwnedSlice(allocator);
}

fn dedupLogs(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var prev: []const u8 = "";
    var dup: usize = 0;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, prev)) {
            dup += 1;
            continue;
        }
        if (dup > 0) try w.print("  [x{d}]\n", .{dup + 1});
        try w.writeAll(line);
        try w.writeByte('\n');
        prev = line;
        dup = 0;
    }
    if (dup > 0) try w.print("  [x{d}]\n", .{dup + 1});
    return out.toOwnedSlice(allocator);
}

fn compressDescribe(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var in_events = false;
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "Events:")) {
            in_events = true;
            try w.writeAll(line);
            try w.writeByte('\n');
            continue;
        }
        // Keep top-level key/value lines and all Events section lines
        if (in_events or (line.len > 0 and line[0] != ' ')) {
            try w.writeAll(line);
            try w.writeByte('\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

test "kubectl get pods compresses" {
    const input = "NAME   READY   STATUS    RESTARTS   AGE\npod-1  1/1     Running   0          5m\npod-2  0/1     Pending   0          1m\n";
    const r = try filterKubectl(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "pod-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Running") != null);
    try std.testing.expect(r.len < input.len);
}

test "kubectl logs dedups" {
    const input = "L1\nL2\nL2\nL2\nL3\n";
    const r = try filterKubectl(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "x3") != null);
}
