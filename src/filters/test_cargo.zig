const std = @import("std");

const State = enum { compiling, testing, failures, summary };

pub fn filterCargoTest(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    // Fast path: all tests passed
    if (std.mem.indexOf(u8, input, "test result: ok") != null and
        std.mem.indexOf(u8, input, "FAILED") == null)
    {
        return extractPassSummary(input, allocator);
    }

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(allocator);
    var state: State = .compiling;
    var failure_blocks: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');

    while (it.next()) |line| {
        state = transition(state, line);
        switch (state) {
            .compiling, .testing => continue,
            .failures => {
                if (std.mem.startsWith(u8, line, "---- ")) failure_blocks += 1;
                if (failure_blocks <= 5) {
                    try w.writeAll(line);
                    try w.writeByte('\n');
                }
            },
            .summary => {
                if (failure_blocks > 5) {
                    try w.print("+{d} more failures\n", .{failure_blocks - 5});
                }
                try w.writeAll(line);
                try w.writeByte('\n');
                failure_blocks = 0; // reset for next test binary
            },
        }
    }
    return out.toOwnedSlice(allocator);
}

fn transition(current: State, line: []const u8) State {
    if (std.mem.startsWith(u8, line, "test result:")) return .summary;
    if (std.mem.startsWith(u8, line, "failures:")) return .failures;
    if (std.mem.indexOf(u8, line, "running ") != null) return .testing;
    return current;
}

fn extractPassSummary(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        if (!std.mem.startsWith(u8, line, "test result:")) continue;
        // Extract passed count: "test result: ok. N passed"
        if (line.len <= "test result: ok. ".len) return allocator.dupe(u8, "cargo test: passed");
        const after = line["test result: ok. ".len..];
        if (std.mem.indexOf(u8, after, " passed")) |end| {
            return std.fmt.allocPrint(allocator, "cargo test: {s} passed", .{after[0..end]});
        }
    }
    return allocator.dupe(u8, "cargo test: ok");
}

test "all pass returns summary" {
    const input =
        \\   Compiling myproject v0.1.0
        \\    Finished test target(s) in 2.5s
        \\     Running unittests src/lib.rs
        \\
        \\running 50 tests
        \\..................................................
        \\test result: ok. 50 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
    ;
    const result = try filterCargoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("cargo test: 50 passed", result);
}

test "failures show details and summary" {
    const input =
        \\   Compiling myproject v0.1.0
        \\    Finished test target(s) in 2.5s
        \\     Running unittests src/main.rs
        \\
        \\running 3 tests
        \\.F.
        \\failures:
        \\
        \\---- test_authentication stdout ----
        \\thread 'test_authentication' panicked at 'assertion failed: user.is_authenticated()'
        \\note: run with `RUST_BACKTRACE=1` for a backtrace
        \\
        \\---- test_database_connection stdout ----
        \\thread 'test_database_connection' panicked at 'connection refused'
        \\
        \\failures:
        \\    test_authentication
        \\    test_database_connection
        \\
        \\test result: FAILED. 1 passed; 2 failed; 0 ignored; 0 measured; 0 filtered out
    ;
    const result = try filterCargoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "test_authentication") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test_database_connection") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test result: FAILED") != null);
    // Compile noise stripped
    try std.testing.expect(std.mem.indexOf(u8, result, "Compiling") == null);
}

test "compile noise stripped" {
    const input =
        \\   Compiling foo v0.1.0
        \\   Downloading bar v1.0.0
        \\    Finished test target(s) in 1.0s
        \\     Running unittests src/lib.rs
        \\
        \\running 5 tests
        \\.....
        \\test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
    ;
    const result = try filterCargoTest(input, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "Compiling") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Downloading") == null);
    try std.testing.expectEqualStrings("cargo test: 5 passed", result);
}

test "empty input returns empty" {
    const result = try filterCargoTest("", std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
