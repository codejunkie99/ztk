//! Claude Code PreToolUse hook integration.
//!
//! `runInit` wires ztk into Claude Code's settings.json so every Bash
//! command is piped through `ztk rewrite`. `runRewrite` is the actual
//! hook handler that Claude Code invokes on stdin per command: it
//! consults permission rules, then either denies, asks, rewrites the
//! command to call through `ztk run`, or passes through unchanged.
//!
//! Exit code protocol expected by Claude Code PreToolUse hooks:
//!     0 -> allow (stdout is the rewritten command, if any)
//!     1 -> no opinion / passthrough
//!     2 -> deny
//!     3 -> ask the user

const std = @import("std");

pub const runInit = @import("claude_init.zig").runInit;
pub const runRewrite = @import("claude_rewrite.zig").runRewrite;

/// Command text Claude Code invokes for our PreToolUse hook.
pub const hook_command: []const u8 = "ztk rewrite";

/// Matcher string Claude Code uses to scope the hook to Bash tool calls.
pub const hook_matcher: []const u8 = "Bash";

/// Basename of Claude Code's settings file within the claude config dir.
pub const settings_filename: []const u8 = "settings.json";

/// Directory (relative to $HOME for global, or cwd for local) holding
/// Claude Code's settings.
pub const claude_dir: []const u8 = ".claude";

test {
    _ = @import("claude_init.zig");
    _ = @import("claude_rewrite.zig");
}
