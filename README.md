# ztk — Zig Token Killer

> CLI proxy that reduces LLM token consumption by 78%+ on real dev sessions. Single Zig binary under 260KB. Zero dependencies.

ztk filters and compresses shell command output before it reaches your LLM's context window. When Claude Code runs `git diff HEAD~5`, ztk intercepts ~92KB of raw diff and compresses it to ~18KB — preserving every changed line while stripping metadata noise.

## Why ztk?

| Metric | ztk |
|--------|-----|
| **Binary size** | 260 KB |
| **External dependencies** | 0 |
| **Filter coverage** | 31 comptime + 25 runtime |
| **Tests** | 217 |
| **Session-aware caching** | Yes (mmap + TTL) |

## Real results

Measured on 109 real commands across a development session:

```
  ┌──────────────────────────────────────────────┐
  │  ⚡ ztk Token Savings                        │
  ├──────────────────────────────────────────────┤
  │  Commands:  109     Input: 396.1K   Output: 86.0K
  │  Saved:     310.0K  (78.2% reduction)
  │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░ 78.2%
  └──────────────────────────────────────────────┘
```

Per-command savings on real shell commands:

```
git status                     87%
git log -10                    85%
git diff HEAD~5                83%
git diff HEAD~10               89%
ls -la                         97%
find src -name *.zig           95%
grep -rn "pub fn" src          82%
cat (code files)               78%
cargo test (all pass)          95%
pytest (all pass)              86%
go test (all pass)             96%
```

## Installation

### Build from source (requires Zig 0.15+)

```bash
git clone https://github.com/user/ztk
cd ztk
zig build -Doptimize=ReleaseSmall
./zig-out/bin/ztk --version
```

### Cross-compilation

```bash
zig build cross
ls zig-out/cross/
# aarch64-macos  x86_64-macos  aarch64-linux-musl  x86_64-linux-musl
```

## Quick start

```bash
# Install the Claude Code hook
ztk init -g

# Test it
ztk run git status
ztk run git diff HEAD~5
ztk run cargo test

# Check savings
ztk stats
```

## How it works

```
Without ztk:                       With ztk:

Claude --git diff--> shell         Claude --git diff--> ztk --> git
  ^                     |            ^                  |      |
  | 92KB (raw)          |            | 18KB (filtered)  | -80% |
  +---------------------+            +------------------+------+
```

Six-phase pipeline:

1. **Parse** — hand-written arg parser, no dependencies
2. **Route** — longest-prefix match over comptime filter registry
3. **Execute** — `std.process.Child` with stdout/stderr capture, exit code preserved
4. **Filter** — per-command compression (31 comptime + 25 runtime regex filters)
5. **Session** — mmap'd cache with TTL-based invalidation for cross-command dedup
6. **Output** — emit filtered result, track savings

## Supported commands

### Git
- `git status` — porcelain v1 and v2 parsing, counts + file list
- `git diff` — compact diff with per-hunk limits, truncation hints
- `git log` — one-line format, trailer stripping
- `git add/commit/push` — reduced to "ok" + essential info

### Test runners
- `cargo test`, `cargo nextest`, `pytest`, `go test`, `npm test`, `vitest`
- All-pass fast path: single summary line
- Failures: show details + summary, cap at 5

### File operations
- `ls` — noise-dir filtering, extension grouping
- `cat` — language-aware signature extraction for large code files
- `find` — group by directory
- `grep` — group by file

### Build & lint
- `cargo build`, `tsc` — errors/warnings only
- `eslint`, `ruff`, `clippy` — group by rule/file
- `zig` — strip build noise, keep errors

### Infrastructure
- `docker` — ps/images/logs compression
- `kubectl` — get tables, logs dedup, describe sections
- `curl` — JSON schema extraction for large responses
- `tree` — noise directory stripping
- `env` — sensitive value masking

### Utilities
- `wc` — compact format with path stripping
- `head`, `tail` — middle-trim large outputs
- `python` — traceback compression
- `json` — structural summary via std.json
- `gh` — PR/issue/run list compression
- `log` — timestamp-aware line deduplication

### Long tail (25 regex-based filters)
make, terraform, helm, rsync, brew, pnpm, pip, bundle, composer, gradle, mvn,
dotnet, wget, prettier, rspec, rubocop, rake, psql, aws, df, ps, systemctl,
ping, shellcheck, yamllint

## Session state

mmap'd state file at `/tmp/ztk-state` (mode 0600):

- Command hash -> filtered output hash mapping (xxhash64)
- Per-entry TTL: fast_changing 30s, medium 2min, slow 5min, immutable never
- Mutation commands invalidate fast_changing entries
- flock-based locking for concurrent safety
- Header validation + fail-safe reset on corruption

## Architecture

- **7,500+ lines of Zig** across 90 files (100-line hard limit per file)
- **217 inline tests** covering filters, session, regex, hooks, executor
- **Thompson NFA regex engine** — linear time, no backtracking
- **SIMD** line splitting + ANSI stripping via `@Vector(16, u8)`
- **Zero external dependencies** — only Zig's standard library
- **Cross-compiles** to 4 platform targets, all under 260KB

## Development

```bash
zig build           # Native build
zig build test      # Run all 217 tests
zig build run       # Run ztk with args
zig build cross     # Cross-compile to 4 targets
```

## License

MIT

## Acknowledgments

Written by [Minimax M2.7](https://www.minimaxi.com). Code generated in a single AI-assisted session.

Inspired by and thankful to the creators of [RTK](https://github.com/rtk-ai/rtk) for pioneering the concept of LLM token compression proxies and proving the idea works. ztk is an independent implementation in Zig that builds on their vision.
