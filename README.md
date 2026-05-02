<p align="center">
  <h1 align="center">⚡ ztk</h1>
  <p align="center"><strong>Stop wasting tokens on raw command output.</strong></p>
  <p align="center">
    <a href="#installation">Install</a> · <a href="#quick-start">Quick Start</a> · <a href="#how-it-works">How It Works</a> · <a href="#supported-commands">Commands</a>
  </p>
</p>

---

Every time your AI coding assistant runs `git diff`, `ls`, or `cargo test`, it dumps thousands of raw tokens into the context window. Most of that is noise. Metadata, whitespace, passing tests, file permissions nobody asked for.

**ztk sits between your AI tool and the shell.** It intercepts command output and compresses it before it reaches the LLM. Same information. Fraction of the tokens.

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

Or build from source (requires Zig 0.16+):

```bash
git clone https://github.com/codejunkie99/ztk
cd ztk && zig build -Doptimize=ReleaseSmall
cp zig-out/bin/ztk ~/.local/bin/
```

The binary is **260KB**. No dependencies. No runtime. Just a single executable.

## Quick Start

```bash
# One command to set up
ztk init -g

# That's it. Every shell command your AI runs now goes through ztk.
# Try it manually:
ztk run git diff HEAD~5
ztk run ls -la src/
ztk run cargo test

# See your savings:
ztk stats

# Update a local source install:
ztk update
```

For Homebrew installs, use `brew upgrade codejunkie99/ztk/ztk`; `ztk update` will not overwrite a Homebrew-managed binary.

## How It Works

```
  Before:                              After:

  AI  ── git diff ──>  shell           AI  ── git diff ──>  ztk  ──>  shell
  ^                       |            ^                     |           |
  |    92,000 tokens      |            |    18,000 tokens    |  filter   |
  +───────────────────────+            +─────────────────────+───────────+
```

ztk runs the command normally, captures the output, compresses it through a six-stage pipeline, and hands back the compressed version. The AI gets the same information in a fraction of the space.

**What gets compressed:**
- Diff metadata and excess context lines → just the changes
- Test runner noise → just failures and a summary
- Directory listings → counts and structure, not every permission bit
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

**231 tests.** Every filter, every edge case, every state machine. The regex engine alone has 11 tests covering catastrophic backtracking prevention.

## For AI Tool Developers

ztk integrates with Claude Code via PreToolUse hooks. The `ztk init -g` command wires everything up automatically.

Adding support for other tools (Cursor, Gemini CLI, Copilot) is straightforward. Each needs a hook adapter in `src/hooks/`. The compression pipeline is tool-agnostic.

## Development

```bash
zig build              # Build
zig build test         # Run 231 tests
zig build run -- stats # Run with args
zig build cross        # Cross-compile to 4 targets
```

## License

MIT

## Acknowledgments

Inspired by and thankful to the creators of [RTK](https://github.com/rtk-ai/rtk) for pioneering LLM token compression proxies and proving the idea works.

Written by [Minimax M2.7](https://www.minimaxi.com).
