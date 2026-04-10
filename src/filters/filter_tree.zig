const std = @import("std");

/// tree output filter. Strips noise directories and caps the output
/// at 80 lines. Detects tree-style output by the presence of the
/// box-drawing characters.
pub fn filterTree(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var kept: usize = 0;
    var stripped: usize = 0;
    var in_noise_dir = false;
    var noise_depth: usize = 0;

    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (kept >= 80) {
            stripped += 1;
            continue;
        }

        // Extract the "name" portion (after tree markers)
        const name = extractName(line);
        const depth = countDepth(line);

        // If we're inside a noise directory and still at deeper depth, skip
        if (in_noise_dir and depth > noise_depth) {
            stripped += 1;
            continue;
        }
        if (in_noise_dir and depth <= noise_depth) {
            in_noise_dir = false;
        }

        if (isNoiseDir(name)) {
            in_noise_dir = true;
            noise_depth = depth;
            try w.writeAll(line);
            try w.writeAll(" [stripped]\n");
            kept += 1;
            continue;
        }

        try w.writeAll(line);
        try w.writeByte('\n');
        kept += 1;
    }
    if (stripped > 0) try w.print("[ztk: {d} lines stripped]\n", .{stripped});
    return out.toOwnedSlice(allocator);
}

fn extractName(line: []const u8) []const u8 {
    // Skip past tree-drawing characters (├ └ │) and spaces.
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        if (c == ' ' or c == '\t' or c == '|') {
            i += 1;
            continue;
        }
        // Multi-byte box-drawing: 0xE2 0x94 0x8x
        if (c == 0xE2 and i + 2 < line.len and line[i + 1] == 0x94) {
            i += 3;
            continue;
        }
        if (c == '-') {
            i += 1;
            continue;
        }
        break;
    }
    return std.mem.trim(u8, line[i..], " \t");
}

fn countDepth(line: []const u8) usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == ' ' or line[i] == '|') {
            depth += 1;
        } else if (line[i] == 0xE2 and i + 2 < line.len) {
            depth += 1;
            i += 2;
        } else break;
    }
    return depth;
}

fn isNoiseDir(name: []const u8) bool {
    const noise = [_][]const u8{
        "node_modules", ".git", "target", "__pycache__",
        ".next",        "dist", "vendor", "build",
        ".venv",        "venv", ".cache",
    };
    for (noise) |n| {
        if (std.mem.startsWith(u8, name, n)) return true;
    }
    return false;
}

test "tree strips noise dirs" {
    const input = "src\n├── main.zig\n├── node_modules\n│   └── foo.js\n└── test.zig\n";
    const r = try filterTree(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "stripped") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "foo.js") == null);
}

test "tree empty" {
    const r = try filterTree("", std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}
