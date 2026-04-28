const std = @import("std");

/// Definition for a runtime (regex-dispatched) filter. Unlike comptime
/// filters, these are matched by command_pattern regex and apply a
/// generic line-stripping/keeping/limiting pipeline.
pub const RuntimeFilterDef = struct {
    /// Regex pattern matching the command (e.g., "^make\\b")
    command_pattern: []const u8,
    /// Lines matching any of these regexes are stripped
    strip_lines: []const []const u8 = &.{},
    /// If non-empty, only lines matching one of these are kept
    keep_lines: []const []const u8 = &.{},
    /// Maximum total lines to output (0 = unlimited)
    max_lines: usize = 0,
    /// Tail lines to keep (last N) — applied after max_lines
    tail_lines: usize = 0,
    /// Message to emit if filtered output is empty
    on_empty: []const u8 = "",
    /// Strip ANSI escape codes before line processing
    strip_ansi: bool = false,
};

pub const filters = [_]RuntimeFilterDef{
    .{
        .command_pattern = "^make\\b",
        .strip_lines = &.{ "^make\\[\\d+", "^\\s*$", "^Nothing to be done" },
        .max_lines = 50,
        .on_empty = "make: ok",
    },
    .{
        .command_pattern = "^terraform\\s+plan",
        .strip_lines = &.{ "^\\s*$", "^Refreshing state" },
        .max_lines = 100,
    },
    .{
        .command_pattern = "^helm\\b",
        .max_lines = 30,
    },
    .{
        .command_pattern = "^rsync\\b",
        .strip_lines = &.{ "^sending incremental", "^total size is" },
        .max_lines = 20,
    },
    .{
        .command_pattern = "^df\\b",
        .max_lines = 20,
    },
    .{
        .command_pattern = "^ps\\b",
        .max_lines = 30,
    },
    .{
        .command_pattern = "^systemctl\\s+status",
        .max_lines = 20,
    },
    .{
        .command_pattern = "^ping\\b",
        .max_lines = 5,
    },
    .{
        .command_pattern = "^shellcheck\\b",
        .max_lines = 50,
    },
    .{
        .command_pattern = "^yamllint\\b",
        .max_lines = 50,
    },
    // Package managers — strip progress/installing lines
    .{
        .command_pattern = "^brew\\s+install",
        .strip_lines = &.{ "^==> Download", "^==> Fetching", "^==> Pour", "^==> Install" },
        .max_lines = 20,
        .on_empty = "brew install: ok",
    },
    .{
        .command_pattern = "^pnpm\\s+install",
        .strip_lines = &.{ "^Progress:", "^Packages:", "^Already up-to-date" },
        .max_lines = 15,
        .on_empty = "pnpm install: ok",
    },
    .{
        .command_pattern = "^pip\\s+install",
        .strip_lines = &.{ "^Collecting", "^Downloading", "^Requirement already" },
        .max_lines = 20,
        .on_empty = "pip install: ok",
    },
    .{
        .command_pattern = "^bundle\\s+install",
        .strip_lines = &.{ "^Using ", "^Fetching " },
        .max_lines = 20,
        .on_empty = "bundle install: ok",
    },
    .{
        .command_pattern = "^composer\\s+install",
        .strip_lines = &.{"^\\s*-\\s*Installing"},
        .max_lines = 20,
        .on_empty = "composer install: ok",
    },
    .{
        .command_pattern = "^gradle\\b",
        .strip_lines = &.{ "^> Task ", "^\\d+ actionable" },
        .max_lines = 30,
    },
    .{
        .command_pattern = "^mvn\\b",
        .strip_lines = &.{ "^\\[INFO\\] Downloading", "^\\[INFO\\] Downloaded", "^\\[INFO\\]\\s*$" },
        .max_lines = 40,
    },
    .{
        .command_pattern = "^dotnet\\s+build",
        .strip_lines = &.{"^\\s*$"},
        .max_lines = 30,
        .on_empty = "dotnet build: ok",
    },
    .{
        .command_pattern = "^wget\\b",
        .strip_lines = &.{ "^\\d+K", "^\\s*\\d+%", "^Resolving ", "^Connecting " },
        .max_lines = 5,
        .on_empty = "wget: ok",
    },
    .{
        .command_pattern = "^prettier\\s+--check",
        .strip_lines = &.{"^Checking formatting"},
        .max_lines = 30,
        .on_empty = "prettier: ok",
    },
    .{
        .command_pattern = "^rspec\\b",
        .strip_lines = &.{ "^\\.+$", "^\\s*$" },
        .max_lines = 50,
    },
    .{
        .command_pattern = "^rubocop\\b",
        .max_lines = 50,
    },
    .{
        .command_pattern = "^rake\\s+test",
        .strip_lines = &.{"^\\s*$"},
        .max_lines = 40,
    },
    .{
        .command_pattern = "^psql\\b",
        .strip_lines = &.{"^-+$"},
        .max_lines = 30,
    },
    .{
        .command_pattern = "^aws\\s+\\w+",
        .max_lines = 50,
    },
};

test "filters list is non-empty" {
    try std.testing.expect(filters.len > 0);
}

test "every filter has a command_pattern" {
    for (filters) |f| {
        try std.testing.expect(f.command_pattern.len > 0);
    }
}
