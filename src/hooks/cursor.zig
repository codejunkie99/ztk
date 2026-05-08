//! Cursor agent preToolUse hook integration.
//!
//! `runInit` wires ztk into Cursor's hooks.json so every Shell
//! tool call is piped through `ztk cursor-rewrite`. `runRewrite`
//! is the hook handler that Cursor invokes on stdin per command:
//! it checks whether ztk has a filter, then either rewrites the
//! command to call through `ztk run`, or passes through unchanged.

const std = @import("std");

pub const runInit = @import("cursor_init.zig").runInit;
pub const runRewrite = @import("cursor_rewrite.zig").runRewrite;

pub const hook_command: []const u8 = "ztk cursor-rewrite";

pub const hook_matcher: []const u8 = "Shell";

pub const hooks_filename: []const u8 = "hooks.json";

pub const cursor_dir: []const u8 = ".cursor";

test {
    _ = @import("cursor_init.zig");
    _ = @import("cursor_rewrite.zig");
}
