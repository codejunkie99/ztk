//! Gemini CLI BeforeTool hook integration.
//!
//! `runInit` wires ztk into Gemini CLI's settings.json so every
//! run_shell_command tool call is piped through `ztk gemini-rewrite`.
//! `runRewrite` is the hook handler that Gemini CLI invokes on stdin
//! per command: it checks whether ztk has a filter, then either
//! rewrites the command to call through `ztk run`, or passes through
//! unchanged.

const std = @import("std");

pub const runInit = @import("gemini_init.zig").runInit;
pub const runRewrite = @import("gemini_rewrite.zig").runRewrite;

pub const hook_command: []const u8 = "ztk gemini-rewrite";

pub const hook_matcher: []const u8 = "run_shell_command";

pub const settings_filename: []const u8 = "settings.json";

pub const gemini_dir: []const u8 = ".gemini";

test {
    _ = @import("gemini_init.zig");
    _ = @import("gemini_init_build.zig");
    _ = @import("gemini_rewrite.zig");
}
