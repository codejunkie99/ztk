const std = @import("std");
const compat = @import("../compat.zig");
const aggressive = @import("files_cat_aggressive.zig");

pub fn filterCat(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    if (isDataFormat(input)) return allocator.dupe(u8, input);

    // Aggressive signature extraction for large code files (>500 bytes)
    if (input.len > 500) {
        if (try aggressive.filterCatAggressive(input, allocator)) |signatures| {
            return signatures;
        }
    }

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    var blank_run: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');

    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            blank_run += 1;
            if (blank_run <= 1) try w.writeByte('\n');
            continue;
        }
        blank_run = 0;
        if (isCommentOnly(trimmed)) continue;
        try w.writeAll(line);
        try w.writeByte('\n');
    }

    const result = try out.toOwnedSlice(allocator);
    if (result.len == 0 or onlyWhitespace(result)) {
        allocator.free(result);
        return allocator.dupe(u8, input);
    }
    return result;
}

fn isDataFormat(input: []const u8) bool {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        // JSON / TOML array
        if (trimmed[0] == '{' or trimmed[0] == '[') return true;
        // YAML document marker
        if (std.mem.eql(u8, trimmed, "---")) return true;
        // YAML top-level key (word followed by colon)
        if (isYamlKeyLine(trimmed)) return true;
        // TOML section header
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') return true;
        return false;
    }
    return false;
}

fn isYamlKeyLine(line: []const u8) bool {
    // word chars followed by `:` followed by space or end-of-line
    if (line.len < 2) return false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (c == ':') {
            if (i == 0) return false;
            if (i + 1 == line.len) return true;
            return line[i + 1] == ' ';
        }
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return false;
}

fn isCommentOnly(trimmed: []const u8) bool {
    if (std.mem.startsWith(u8, trimmed, "//")) return true;
    if (std.mem.startsWith(u8, trimmed, "#")) return true;
    if (std.mem.startsWith(u8, trimmed, "--")) return true;
    if (std.mem.startsWith(u8, trimmed, "/*")) return true;
    if (std.mem.startsWith(u8, trimmed, "*/")) return true;
    if (std.mem.startsWith(u8, trimmed, "*")) return true;
    return false;
}

fn onlyWhitespace(s: []const u8) bool {
    for (s) |c| if (c != ' ' and c != '\t' and c != '\r' and c != '\n') return false;
    return true;
}

test "strips blank runs and line comments" {
    const input =
        \\const x = 1;
        \\// this is a comment
        \\
        \\
        \\
        \\const y = 2;
        \\# shell-style comment
        \\const z = 3;
    ;
    const r = try filterCat(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "const x = 1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "const y = 2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "const z = 3;") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "this is a comment") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "shell-style") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "\n\n\n") == null);
}

test "json passthrough unchanged" {
    const input =
        \\{
        \\  "key": "value",
        \\  "n": 1
        \\}
    ;
    const r = try filterCat(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}

test "empty-output safety returns input" {
    const input = "// only a comment\n# and another\n";
    const r = try filterCat(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}
