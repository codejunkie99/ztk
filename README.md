<p align="center">
  <h1 align="center">⚡ ztk</h1>
  <p align="center"><strong>Stop wasting tokens on raw command output.</strong></p>
  <p align="center">
    <a href="#installation">Install</a> · <a href="#quick-start">Quick Start</a> · <a href="#how-it-works">How It Works</a> · <a href="#supported-commands">Commands</a>
  </p>
</p>

---

Every time an AI coding agent runs `git diff`, `ls`, or `cargo test`, it dumps thousands of raw tokens into the context window. Most of that is noise. Metadata, whitespace, passing tests, file permissions nobody asked for.

**ztk sits between your AI agent and the shell.** It supports automatic interception for **Claude Code**, **Cursor Agent**, and **Gemini CLI** — each through their native hook mechanisms. You can also run any command manually through `ztk run`.

<p align="center">
  <img src="assets/stats-screenshot.svg" alt="ztk stats, 256 commands, 5.8M saved, 90.6% reduction" width="700">
</p>

## The numbers

From a real 256-command development session:

| | Before ztk | After ztk |
|---|---|---|
| `git diff HEAD~5` (92KB) | 92,000 tokens | **18,000 tokens** |
| `ls -la src/` (2KB) | 2,000 tokens | **53 tokens** |
| `grep -rn "fn" src/` (14KB) | 14,000 tokens | **400 tokens** |
| `cargo test` (all pass) | 397 tokens | **21 tokens** |
| `find src -name "*.zig"` (2KB) | 2,000 tokens | **96 tokens** |
| `cat main.zig` (5.8KB) | 5,800 tokens | **1,252 tokens** |

**90.6% overall reduction.** 5.8 million tokens saved across 256 commands.

## Installation

```bash
brew install codejunkie99/ztk/ztk
```

Or install a prebuilt binary from the latest release (no Zig required):

```bash
case "$(uname -m)-$(uname -s)" in
  arm64-Darwin) asset=ztk-aarch64-macos.tar.gz ;;
  x86_64-Darwin) asset=ztk-x86_64-macos.tar.gz ;;
  aarch64-Linux) asset=ztk-aarch64-linux-musl.tar.gz ;;
  x86_64-Linux) asset=ztk-x86_64-linux-musl.tar.gz ;;
  *) echo "unsupported platform" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/codejunkie99/ztk/releases/latest/download/$asset" | tar -xz
install -m 755 ztk ~/.local/bin/ztk
```

You can also build from source (requires Zig 0.16+):

```bash
git clone https://github.com/codejunkie99/ztk
cd ztk && zig build -Doptimize=ReleaseSmall
cp zig-out/bin/ztk ~/.local/bin/
```

The binary is **260KB**. No dependencies. No runtime. Just a single executable.

## Quick Start

```bash
# Set up all detected agents (Claude Code, Cursor, Gemini CLI)
ztk init -g

# ztk detects which agent config directories exist (.claude/, .cursor/,
# .gemini/) and installs hooks only for those agents.

# Try it manually:
ztk run git diff HEAD~5
ztk run ls -la src/
ztk run cargo test
ztk run --raw ls -la src/  # exact output when names/details matter

# If Claude Code auto-mode should not prompt on every rewrite:
ztk init -g --skip-permissions

# See your savings:
ztk stats

# Update a local source install:
ztk update
```

For Homebrew installs, use `brew upgrade codejunkie99/ztk/ztk`; `ztk update` will not overwrite a Homebrew-managed binary.

## Claude Code Permissions

Claude Code users who run in Auto mode should install the hook with:

```bash
ztk init -g --skip-permissions
```

That makes the ztk hook return `allow` for commands it rewrites, so Claude Code does not stop on every `ztk run ...` wrapper. Your `permissions.deny` and `permissions.ask` rules still apply to the rewritten command, so keep explicit rules for dangerous actions:

```json
{
  "permissions": {
    "deny": ["Bash(rm -rf*)", "Bash(git push --force*)"],
    "ask": ["Bash(npm publish*)"]
  }
}
```

If you already installed `ztk rewrite` without the flag, remove the old ztk `PreToolUse` hook entry from `.claude/settings.json`, then run `ztk init -g --skip-permissions` again.

## How It Works

```
  Before:                              After:

  AI  ── git diff ──>  shell           AI  ── git diff ──>  ztk  ──>  shell
  ^                       |            ^                     |           |
  |    92,000 tokens      |            |    18,000 tokens    |  filter   |
  +───────────────────────+            +─────────────────────+───────────+
```

ztk runs the command normally, captures the output, compresses it through a six-stage pipeline, and hands back the compressed version. The AI gets the same information in a fraction of the space.

The hook matcher also recognizes path-qualified executables such as `/bin/ls`, `/usr/bin/find`, and `/opt/homebrew/bin/git status`, so agents do not bypass compression by spelling the same tool with an absolute path.

File-listing filters preserve useful payloads. `ls` keeps filenames for bounded listings, and `find` keeps the first set of matching paths before truncating. ztk should remove command-output noise, not hide the names or paths the agent asked for.

**What gets compressed:**
- Diff metadata and excess context lines → just the changes
- Test runner noise → just failures and a summary
- Directory listings → counts and structure plus useful names, not every permission bit
- Log files → deduplicated with counts
- Code files → signatures and declarations, not function bodies

**What never gets touched:**
- Error messages (you need those)
- Exit codes (always preserved)
- Small outputs under 80 bytes (not worth compressing)
- Data formats like JSON, YAML, TOML (no comment stripping)

## Supported Commands

### Built-in filters across every category

**Git**: status, diff, log, add, commit, push
**Test runners**: cargo test, cargo nextest, pytest, go test, npm test, npm run test, pnpm test, yarn test, jest, vitest, npx jest, npx vitest, Playwright
**File ops**: ls, cat, find, grep, rg, wc, head, tail, tree
**Build tools**: cargo build, cargo check, go build, tsc, zig build
**Linters**: eslint, ruff, mypy, clippy, golangci-lint
**Infrastructure**: docker, docker compose, kubectl, curl, env
**Utilities**: json, gh, gh checks, python tracebacks, log deduplication

Plus **25 regex-based filters** for make, terraform, helm, brew, pip, pnpm, bundle, gradle, mvn, dotnet, wget, prettier, rspec, rubocop, rake, psql, aws, and more.

Commands ztk doesn't recognize pass through untouched. It never makes things worse.

## Session Memory

ztk remembers what it showed you.

If you run `git status` three times and nothing changed, the second and third responses say so in a single line instead of repeating the full output. This is powered by an mmap'd cache with per-command TTLs:

- Fast-changing commands (git status, ls): 30 second cache
- Medium commands (test runners): 2 minute cache
- Slow-changing commands (git log): 5 minute cache

Mutation commands like `git add` automatically invalidate related caches.

## What Makes It Different

**260KB binary.** Not 5MB, not 50MB. A quarter megabyte. Starts in under 1ms.

**Zero dependencies.** No package manager, no runtime, no shared libraries. Built entirely on Zig's standard library. Cross-compiles to macOS, Linux, and Windows from any platform.

**Thompson NFA regex engine.** The runtime filter system uses a custom regex engine built from scratch. Linear time guaranteed. No catastrophic backtracking, ever. ~400 lines of Zig.

**SIMD text processing.** Line splitting and ANSI escape stripping use `@Vector(16, u8)` for hardware-accelerated processing on both ARM NEON and x86 SSE2.

**270+ tests.** Every filter, every edge case, every state machine. The regex engine alone has 11 tests covering catastrophic backtracking prevention.

## Supported Agents

| Agent | Hook mechanism | Init |
|---|---|---|
| **Claude Code** | `PreToolUse` hook in `.claude/settings.json` | `ztk init -g` |
| **Cursor Agent** | `PreToolUse` hook in `.cursor/hooks.json` | `ztk init -g` |
| **Gemini CLI** | `BeforeTool` hook in `.gemini/settings.json` | `ztk init -g` |

`ztk init` detects which agents are present and installs hooks for all of them. The compression pipeline is agent-agnostic — `ztk run <command>` works as a standalone wrapper regardless of which agent invokes it.

## Development

```bash
zig build              # Build
zig build test         # Run unit tests
zig build run -- stats # Run with args
zig build cross        # Cross-compile release binaries
```

## License

MIT

## Acknowledgments

Inspired by and thankful to the creators of [RTK](https://github.com/rtk-ai/rtk) for pioneering LLM token compression proxies and proving the idea works.

Written by [Minimax M2.7](https://www.minimaxi.com).
