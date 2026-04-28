const std = @import("std");
const cargo = @import("filter_build_cargo.zig");
const tsc = @import("filter_build_tsc.zig");

pub const filterCargoBuild = cargo.filterCargoBuild;
pub const filterTsc = tsc.filterTsc;

test "cargo build no errors" {
    const input =
        \\   Compiling foo v0.1.0
        \\    Finished dev [unoptimized + debuginfo] target(s) in 1.23s
    ;
    const r = try filterCargoBuild(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("cargo build: ok", r);
}

test "cargo build keeps error blocks with continuation" {
    const input =
        \\   Compiling foo v0.1.0
        \\error[E0425]: cannot find value `x` in this scope
        \\  --> src/main.rs:3:5
        \\   |
        \\ 3 |     x + 1
        \\   |     ^ not found in this scope
        \\
        \\warning: unused variable: `y`
        \\  --> src/main.rs:5:9
        \\    Finished dev target(s) in 1.0s
    ;
    const r = try filterCargoBuild(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "error[E0425]") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "not found in this scope") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "warning: unused variable") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Compiling") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "Finished") == null);
}

test "cargo build strips rustc code gutters but keeps locations and notes" {
    const input =
        \\error[E0425]: cannot find value `missing` in this scope
        \\  --> src/lib.rs:12:9
        \\   |
        \\12 |         missing
        \\   |         ^^^^^^^ not found in this scope
        \\
        \\warning: unused variable: `x`
        \\  --> src/main.rs:3:9
        \\   |
        \\3  |     let x = 1;
        \\   |         ^ help: if this is intentional, prefix it with an underscore: `_x`
    ;
    const r = try filterCargoBuild(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(r.len < input.len);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/lib.rs:12:9") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "not found in this scope") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "prefix it with an underscore") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "12 |") == null);
    try std.testing.expect(std.mem.indexOf(u8, r, "^^^^^^") == null);
}

test "cargo build preserves notes from multiple diagnostic blocks" {
    const input =
        \\error[E0308]: mismatched types
        \\  --> src/lib.rs:8:5
        \\   |
        \\8  |     42
        \\   |     ^^ expected `String`, found integer
        \\
        \\error: aborting due to previous error
        \\
        \\warning: unreachable code
        \\  --> src/main.rs:4:5
        \\   |
        \\4  |     println!("x");
        \\   |     ^^^^^^^^^^^^^ unreachable statement
    ;
    const r = try filterCargoBuild(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "mismatched types") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "expected `String`, found integer") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "unreachable statement") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "aborting due to previous error") == null);
}

test "tsc groups errors by file" {
    const input =
        \\src/a.ts(10,5): error TS2304: Cannot find name 'foo'.
        \\src/a.ts(12,1): error TS2322: Type 'x' not assignable.
        \\src/b.ts(3,9): error TS2345: Argument type mismatch.
        \\src/a.ts(20,2): error TS2554: Wrong arg count.
        \\src/a.ts(25,2): error TS2554: Another.
    ;
    const r = try filterTsc(input, std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/a.ts: 4 errors") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "src/b.ts: 1 errors") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "TS2304") != null);
}

test "empty inputs return ok" {
    const r1 = try filterCargoBuild("", std.testing.allocator);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqualStrings("cargo build: ok", r1);
    const r2 = try filterTsc("", std.testing.allocator);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqualStrings("tsc: ok", r2);
}
