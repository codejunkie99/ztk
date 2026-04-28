const std = @import("std");
const compat = @import("../compat.zig");

const ErrorEntry = struct {
    file: []const u8,
    line: []const u8,
    code: []const u8,
    message: []const u8,
};

pub fn filterMypy(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "mypy: ok");

    var errors: std.ArrayList(ErrorEntry) = .empty;
    defer errors.deinit(allocator);
    var fileless: std.ArrayList([]const u8) = .empty;
    defer fileless.deinit(allocator);

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "Found ") and std.mem.indexOf(u8, line, " error") != null) continue;
        if (std.mem.startsWith(u8, line, "Success:")) return allocator.dupe(u8, "mypy: ok");
        const parsed = parseDiagnostic(line) orelse {
            if (std.mem.indexOf(u8, line, "error:") != null) try fileless.append(allocator, line);
            continue;
        };
        if (std.mem.eql(u8, parsed.severity, "note")) continue;
        try errors.append(allocator, .{
            .file = parsed.file,
            .line = parsed.line,
            .code = parsed.code,
            .message = parsed.message,
        });
    }

    if (errors.items.len == 0 and fileless.items.len == 0) return allocator.dupe(u8, "mypy: ok");

    var out: std.ArrayList(u8) = .empty;
    const w = compat.listWriter(&out, allocator);
    for (fileless.items) |line| try w.print("{s}\n", .{line});
    if (errors.items.len > 0) {
        try w.print("mypy: {d} errors in {d} files\n", .{ errors.items.len, countFiles(errors.items) });
        try writeCodes(w, errors.items);
        var emitted_files: std.ArrayList([]const u8) = .empty;
        defer emitted_files.deinit(allocator);
        for (errors.items) |err| {
            if (!contains(emitted_files.items, err.file)) {
                try emitted_files.append(allocator, err.file);
                try w.print("{s}\n", .{err.file});
            }
            if (err.code.len > 0) {
                try w.print("  L{s} [{s}] {s}\n", .{ err.line, err.code, err.message });
            } else {
                try w.print("  L{s} {s}\n", .{ err.line, err.message });
            }
        }
    }
    return out.toOwnedSlice(allocator);
}

const Parsed = struct {
    file: []const u8,
    line: []const u8,
    severity: []const u8,
    message: []const u8,
    code: []const u8,
};

fn parseDiagnostic(line: []const u8) ?Parsed {
    const c1 = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const rest1 = std.mem.trimStart(u8, line[c1 + 1 ..], " ");
    const c2 = std.mem.indexOfScalar(u8, rest1, ':') orelse return null;
    const line_no = rest1[0..c2];
    if (!allDigits(line_no)) return null;

    var rest = std.mem.trimStart(u8, rest1[c2 + 1 ..], " ");
    if (rest.len > 0 and std.ascii.isDigit(rest[0])) {
        const c3 = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
        const col = rest[0..c3];
        if (!allDigits(col)) return null;
        rest = std.mem.trimStart(u8, rest[c3 + 1 ..], " ");
    }

    const c4 = std.mem.indexOf(u8, rest, ": ") orelse return null;
    const severity = rest[0..c4];
    if (!std.mem.eql(u8, severity, "error") and
        !std.mem.eql(u8, severity, "warning") and
        !std.mem.eql(u8, severity, "note")) return null;
    const raw_message = rest[c4 + 2 ..];
    const parsed_msg = splitCode(raw_message);
    return .{
        .file = line[0..c1],
        .line = line_no,
        .severity = severity,
        .message = parsed_msg.message,
        .code = parsed_msg.code,
    };
}

const MessageParts = struct { message: []const u8, code: []const u8 };

fn splitCode(message: []const u8) MessageParts {
    if (message.len < 3 or message[message.len - 1] != ']') return .{ .message = message, .code = "" };
    const open = std.mem.lastIndexOfScalar(u8, message, '[') orelse return .{ .message = message, .code = "" };
    if (open == 0 or message[open - 1] != ' ') return .{ .message = message, .code = "" };
    return .{
        .message = std.mem.trimEnd(u8, message[0 .. open - 1], " \t"),
        .code = message[open + 1 .. message.len - 1],
    };
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn contains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn countFiles(errors: []const ErrorEntry) usize {
    var count: usize = 0;
    for (errors, 0..) |err, i| {
        var seen = false;
        for (errors[0..i]) |prev| {
            if (std.mem.eql(u8, prev.file, err.file)) {
                seen = true;
                break;
            }
        }
        if (!seen) count += 1;
    }
    return count;
}

fn writeCodes(w: anytype, errors: []const ErrorEntry) error{OutOfMemory}!void {
    var wrote = false;
    for (errors, 0..) |err, i| {
        if (err.code.len == 0) continue;
        var count: usize = 1;
        var seen = false;
        for (errors[0..i]) |prev| {
            if (std.mem.eql(u8, prev.code, err.code)) {
                seen = true;
                break;
            }
        }
        if (seen) continue;
        for (errors[i + 1 ..]) |next| {
            if (std.mem.eql(u8, next.code, err.code)) count += 1;
        }
        if (!wrote) {
            try w.writeAll("codes: ");
            wrote = true;
        } else {
            try w.writeAll(", ");
        }
        try w.print("{s} ({d})", .{ err.code, count });
    }
    if (wrote) try w.writeByte('\n');
}

test "mypy groups by file and code" {
    const input =
        \\src/app.py:12: error: Incompatible return value type (got "int", expected "str")  [return-value]
        \\src/db.py:44: error: Item "None" of "User | None" has no attribute "email"  [union-attr]
        \\Found 2 errors in 2 files (checked 12 source files)
    ;
    const r = try filterMypy(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "mypy: 2 errors in 2 files") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "codes: return-value (1), union-attr (1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "L12 [return-value] Incompatible") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Found 2 errors") == null);
}
