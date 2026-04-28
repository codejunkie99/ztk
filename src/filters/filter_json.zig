const std = @import("std");
const compat = @import("../compat.zig");

/// json output filter. Emits a structural summary instead of values.
/// Short inputs (<500 bytes) pass through unchanged. Long inputs get
/// their top-level keys listed with inferred types.
pub fn filterJson(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");
    if (input.len < 500) return allocator.dupe(u8, input);

    // Try parsing with std.json to get a typed tree
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch {
        // Fall back to key-name extraction
        return emitKeys(input, allocator);
    };
    defer parsed.deinit();

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try writeSchema(w, parsed.value, 0);
    return out.toOwnedSlice(allocator);
}

fn writeSchema(w: anytype, v: std.json.Value, depth: usize) !void {
    if (depth > 3) {
        try w.writeAll("...\n");
        return;
    }
    switch (v) {
        .object => |obj| {
            try w.writeAll("{\n");
            var it = obj.iterator();
            var count: usize = 0;
            while (it.next()) |e| {
                if (count >= 20) {
                    try w.writeAll("  ...\n");
                    break;
                }
                for (0..depth + 1) |_| try w.writeAll("  ");
                try w.print("{s}: {s}\n", .{ e.key_ptr.*, typeName(e.value_ptr.*) });
                count += 1;
            }
            for (0..depth) |_| try w.writeAll("  ");
            try w.writeAll("}\n");
        },
        .array => |arr| {
            try w.print("array[{d}]", .{arr.items.len});
            if (arr.items.len > 0) {
                try w.writeAll(" of ");
                try w.writeAll(typeName(arr.items[0]));
            }
            try w.writeByte('\n');
        },
        else => try w.writeAll(typeName(v)),
    }
}

fn typeName(v: std.json.Value) []const u8 {
    return switch (v) {
        .null => "null",
        .bool => "bool",
        .integer => "int",
        .float => "float",
        .number_string => "number",
        .string => "string",
        .array => "array",
        .object => "object",
    };
}

fn emitKeys(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    try w.writeAll("json (unparseable, raw preview):\n");
    const preview_len = @min(input.len, 300);
    try w.writeAll(input[0..preview_len]);
    try w.writeByte('\n');
    return out.toOwnedSlice(allocator);
}

test "json short passes through" {
    const input = "{\"ok\":true}";
    const r = try filterJson(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings(input, r);
}

test "json long emits schema" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = compat.listWriter(&buf, std.testing.allocator);
    try w.writeAll("{\"id\":42,\"name\":\"test\",\"nested\":{\"key\":\"value\"},\"items\":[1,2,3],\"extra\":\"");
    var i: usize = 0;
    while (i < 500) : (i += 1) try w.writeByte('x');
    try w.writeAll("\"}");

    const r = try filterJson(buf.items, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "id") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "name") != null);
    try std.testing.expect(r.len < buf.items.len);
}
