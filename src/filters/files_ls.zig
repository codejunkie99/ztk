const std = @import("std");
const parse = @import("files_ls_parse.zig");
const ext_mod = @import("files_ls_ext.zig");
const fmt = @import("files_ls_format.zig");

/// Two-mode `ls`/`ls -la` filter. When the listing has more than 10 files,
/// switches to a smart summary that counts files by extension and shows
/// only the first three directories. For shorter listings, falls back to
/// the original full-list output so a small `ls` stays readable.
pub fn filterLs(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "ls: empty");

    var dirs: std.ArrayList([]const u8) = .{};
    defer dirs.deinit(allocator);
    var files: std.ArrayList([]const u8) = .{};
    defer files.deinit(allocator);
    var counts: ext_mod.ExtCounts = .{};

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "total ")) continue;
        const name = parse.extractName(line) orelse continue;
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (parse.isNoise(name)) continue;
        if (line[0] == 'd') {
            try dirs.append(allocator, name);
        } else {
            try files.append(allocator, name);
            counts.record(name);
        }
    }

    if (files.items.len <= 10) {
        return fmt.formatVerbose(dirs.items, files.items, allocator);
    }
    return fmt.formatSmart(dirs.items, files.items, &counts, allocator);
}

test {
    _ = @import("files_ls_parse.zig");
    _ = @import("files_ls_ext.zig");
    _ = @import("files_ls_format.zig");
    _ = @import("files_ls_test.zig");
}
