const std = @import("std");

/// curl output filter. Auto-detects JSON and emits a schema for large
/// responses. HTML gets tag-stripped. Everything else passes through
/// capped at 50 lines.
pub fn filterCurl(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Find first non-whitespace byte
    var i: usize = 0;
    while (i < input.len and (input[i] == ' ' or input[i] == '\t' or input[i] == '\n' or input[i] == '\r')) : (i += 1) {}
    if (i >= input.len) return allocator.dupe(u8, input);

    if (input[i] == '{' or input[i] == '[') return filterJsonResponse(input[i..], allocator);
    if (input[i] == '<') return filterHtml(input, allocator);
    return capLines(input, 50, allocator);
}

fn filterJsonResponse(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    // Short JSON — keep as-is
    if (input.len < 500) return allocator.dupe(u8, input);
    // Large — emit schema summary
    return emitSchema(input, allocator);
}

fn emitSchema(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    try w.writeAll("json schema:\n");
    // Walk top-level keys via bracket depth tracking
    var depth: i32 = 0;
    var in_str = false;
    var key_start: ?usize = null;
    var keys: usize = 0;
    var i: usize = 0;
    while (i < input.len and keys < 20) : (i += 1) {
        const c = input[i];
        if (in_str) {
            if (c == '\\') {
                i += 1;
                continue;
            }
            if (c == '"') {
                in_str = false;
                if (depth == 1 and key_start != null) {
                    const end_i = i;
                    const start_i = key_start.? + 1;
                    // Check if followed by a colon (it's a key, not a value)
                    var j = end_i + 1;
                    while (j < input.len and (input[j] == ' ' or input[j] == '\t')) : (j += 1) {}
                    if (j < input.len and input[j] == ':') {
                        try w.print("  {s}\n", .{input[start_i..end_i]});
                        keys += 1;
                    }
                    key_start = null;
                }
            }
        } else {
            if (c == '"') {
                in_str = true;
                if (depth == 1) key_start = i;
            } else if (c == '{' or c == '[') {
                depth += 1;
            } else if (c == '}' or c == ']') {
                depth -= 1;
            }
        }
    }
    if (keys == 0) return allocator.dupe(u8, input[0..@min(500, input.len)]);
    return out.toOwnedSlice(allocator);
}

fn filterHtml(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    // Keep <title> and strip tags
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    if (std.mem.indexOf(u8, input, "<title>")) |s| {
        if (std.mem.indexOf(u8, input[s..], "</title>")) |e| {
            try w.writeAll("title: ");
            try w.writeAll(input[s + 7 .. s + e]);
            try w.writeByte('\n');
        }
    }
    try w.print("[html body: {d} bytes]\n", .{input.len});
    return out.toOwnedSlice(allocator);
}

fn capLines(input: []const u8, max: usize, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var it = std.mem.splitScalar(u8, input, '\n');
    var n: usize = 0;
    while (it.next()) |line| {
        if (n >= max) break;
        try w.writeAll(line);
        try w.writeByte('\n');
        n += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "curl short json passes through" {
    const input = "{\"ok\":true}";
    const r = try filterCurl(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}

test "curl html extracts title" {
    const input = "<html><head><title>Hello</title></head><body>...</body></html>";
    const r = try filterCurl(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "Hello") != null);
}
