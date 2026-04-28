const std = @import("std");

/// Strip ANSI escape sequences from input. Uses SIMD to fast-scan for
/// the ESC byte (0x1b); if none found, returns a copy without allocation
/// overhead beyond the dup. When ESC is found, walks bytes and skips CSI
/// sequences (ESC [ params finalByte).
pub fn stripAnsi(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Fast path: SIMD scan for ESC byte
    if (!containsEsc(input)) {
        const copy = try allocator.alloc(u8, input.len);
        @memcpy(copy, input);
        return copy;
    }

    // Slow path: walk and skip CSI sequences
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            // Skip CSI sequence: ESC [ params final_byte
            i += 2;
            while (i < input.len and input[i] >= 0x20 and input[i] <= 0x3F) : (i += 1) {}
            if (i < input.len and input[i] >= 0x40 and input[i] <= 0x7E) i += 1;
        } else {
            try buf.append(allocator, input[i]);
            i += 1;
        }
    }
    return try buf.toOwnedSlice(allocator);
}

fn containsEsc(input: []const u8) bool {
    const Vec = @Vector(16, u8);
    const esc: Vec = @splat(@as(u8, 0x1b));
    var i: usize = 0;
    while (i + 16 <= input.len) : (i += 16) {
        const chunk: Vec = input[i..][0..16].*;
        if (@as(u16, @bitCast(chunk == esc)) != 0) return true;
    }
    while (i < input.len) : (i += 1) {
        if (input[i] == 0x1b) return true;
    }
    return false;
}

test "stripAnsi removes color codes" {
    const input = "\x1b[31mERROR\x1b[0m: something failed";
    const result = try stripAnsi(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("ERROR: something failed", result);
}

test "stripAnsi passthrough clean text" {
    const input = "no ansi here";
    const result = try stripAnsi(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("no ansi here", result);
}

test "stripAnsi handles bold and underline" {
    const input = "\x1b[1mbold\x1b[22m \x1b[4munder\x1b[24m";
    const result = try stripAnsi(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("bold under", result);
}

test "stripAnsi empty" {
    const result = try stripAnsi("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
