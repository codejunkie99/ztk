const std = @import("std");
const diag_block = @import("filter_diag_block.zig");

pub fn filterCargoBuild(input: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    return diag_block.filterRustc(input, "cargo build: ok", allocator);
}
