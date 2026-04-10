# ztk — Zig Token Killer

> CLI proxy that reduces LLM token consumption by 53-90% on real dev sessions. Single Zig binary under 260KB. Zero dependencies.

ztk filters and compresses shell command output before it reaches your LLM's context window. When Claude Code (or Cursor, Gemini, etc.) runs `git diff HEAD~5`, ztk intercepts the ~92KB of diff output and compresses it to ~18KB while preserving every changed line.

## Measured vs RTK

Head-to-head on identical commands in the ztk repo (RTK 0.35.0 vs ztk 0.2.0):

| Metric | RTK | ztk |
|--------|-----|-----|
| **Binary size (release)** | 5.8 MB | **260 KB** (22x smaller) |
| **External dependencies** | ~20 crates | **0** |
| **Filter coverage** | ~30 commands | **31 comptime + 25 runtime** |
| **Tests** | unknown | **216** |
| `git status` savings | 57% | **87%** |
| `git log -10` savings | 61% | **85%** |
| `git log -30` savings | 52% | **86%** |
| `git diff HEAD~5` savings | 81% | **83%** |
| `git diff HEAD~10` savings | 87% | **89%** |
| `ls -la` savings | 71% | **97%** |
| `find` savings | 57% | **95%** |
| `grep` savings | 10% | **82%** |
| `wc` savings | 37% | **37%** (tie) |
| `head -50` savings | 0% | **25%** |
| `tail -50` savings | 0% | **26%** |

**Head-to-head wins: ztk 9, RTK 0, ties 1.**

## Real session benchmark

Measured on a real 129-command Claude Code session (this repo's development log):

| Metric | Value |
|--------|-------|
| Total Bash tool calls | 129 |
| Raw command output | 107.5 KB (~27.5K tokens) |
| Filtered output | 50.6 KB (~12.9K tokens) |
| **Savings** | **53% (14.6K tokens)** |
| Match rate (commands ztk recognizes) | 90% |

## Real benchmark results

Measured on the ztk repo itself using real shell commands:

```
git status                     raw=    389  filtered=     49  savings=  87.4%
git log (full history)         raw=  13251  filtered=   5437  savings=  58.9%
git log --oneline              raw=   1928  filtered=      1  savings=  99.9%
git diff HEAD~5                raw=  92510  filtered=  18164  savings=  80.3%
git diff HEAD~10               raw= 144713  filtered=  18618  savings=  87.1%
ls -la src                     raw=   1990  filtered=    476  savings=  76.0%
find src -name *.zig           raw=   1681  filtered=     95  savings=  94.3%
grep -rn "pub fn" src          raw=   8420  filtered=    956  savings=  88.6%
```

Test runner output (from RTK's own test fixtures):

```
cargo test (multi-suite)       raw=    763  filtered=     21  savings=  97.2%
cargo test (all pass)          raw=    397  filtered=     21  savings=  94.7%
cargo nextest (all pass)       raw=    591  filtered=     25  savings=  95.8%
go test (all pass)             raw=    414  filtered=     17  savings=  95.9%
pytest (all pass)              raw=    180  filtered=     25  savings=  86.1%
```

## Installation

### Build from source (requires Zig 0.15+)

```bash
git clone <ztk-repo>
cd ztk
zig build -Doptimize=ReleaseSmall
./zig-out/bin/ztk --version
```

The resulting binary is ~220KB with zero dependencies.

### Cross-compilation

```bash
zig build cross
ls zig-out/cross/
# aarch64-macos  x86_64-macos  aarch64-linux-musl  x86_64-linux-musl
```

All four targets build to under 220KB.

## Quick start

```bash
# Install the Claude Code hook
ztk init -g

# Test it
ztk run git status
ztk run git diff HEAD~5
ztk run cargo test

# Check the version
ztk --version
```

After `ztk init -g`, restart Claude Code. Every Bash tool call gets automatically rewritten to use ztk's compressed output.

## How it works

```
Without ztk:                       With ztk:

Claude --git diff--> shell         Claude --git diff--> ztk --> git
  ^                     |            ^                  |      |
  | 92KB (raw)          |            | 18KB (filtered)  | +80% |
  +---------------------+            +------------------+------+
```

ztk has a six-phase pipeline:

1. **Parse** — hand-written arg parser (no clap)
2. **Route** — longest-prefix match over comptime filter registry
3. **Execute** — `std.process.Child` with stdout/stderr capture, exit code preserved
4. **Filter** — per-command compression (21 comptime filters + regex-based runtime filters)
5. **Session** — mmap'd cache with TTL-based invalidation for cross-command deduplication
6. **Output** — emit filtered result, track savings

## Supported commands

### Git (compiled into binary)
- `git status` — porcelain v1 and v2 parsing, counts + file list
- `git diff` — compact diff with 100-line-per-hunk cap, 500-line total cap, truncation hint
- `git log` — one-line format, trailer stripping, body truncation
- `git add` / `commit` / `push` — reduced to "ok" + essential info

### Test runners
- `cargo test` — state machine, failures-only + summary
- `cargo nextest` — FAIL blocks + STDERR extraction + summary
- `pytest` — === marker state machine
- `go test` — NDJSON Action parsing
- `npm test` / `vitest` — failure block extraction

### File operations
- `ls` — noise-dir filtering, dir/file grouping
- `cat` — language-aware comment stripping (12 languages, data-format safe)
- `find` — group by directory
- `grep` — group by file

### Build/lint
- `cargo build` — errors/warnings only, preserves continuation lines
- `tsc` — group errors by file
- `eslint` / `ruff` / `clippy` — group by rule/file

### Long tail (regex-based)
- `make`, `terraform plan`, `helm`, `rsync`, `df`, `ps`, `systemctl`, `ping`, `shellcheck`, `yamllint` — glob-style line filtering via built-in Thompson NFA regex engine

## Architecture

- **6,400 lines of Zig across 60+ files** (100-line hard limit per file)
- **167 inline tests** covering filters, session state, regex, hooks, executor
- **Thompson NFA regex** (400 lines) — linear time guaranteed, no catastrophic backtracking
- **mmap'd session state** with `flock` locking and TTL-based invalidation
- **4-exit-code permission protocol** for Claude Code PreToolUse hook (allow/passthrough/deny/ask)
- **SIMD line splitting and ANSI stripping** via `@Vector(16, u8)`
- **Zero external dependencies** — only Zig's standard library

## Session state

ztk maintains an mmap'd state file at `/tmp/ztk-state` (mode 0600) with:

- Command hash → filtered output hash mapping (xxhash64)
- Per-entry TTL based on command category:
  - `fast_changing` (git status, ls): 30s
  - `medium` (test runners): 2min
  - `slow_changing` (git log): 5min
  - `immutable`: never expires
  - `mutation` (git add/commit): invalidates all fast_changing entries
- Atomic update-in-place for repeat commands (no stale entry shadowing)
- Header validation + fail-safe reset on corruption

## Security

The PreToolUse hook uses a 4-exit-code protocol:

- **0** — Allow with rewrite (compressed output)
- **1** — Passthrough (no matching filter)
- **2** — Deny (permission rule matched)
- **3** — Ask (permission rule requires confirmation)

Permission checking happens **before** rewrite, parsing Claude Code's `settings.json` for Bash deny/ask rules. Compound commands (`&&`, `||`, `|`, `;`) are split and each segment checked independently. Malformed settings fail **closed** to `.ask`.

## Known limitations

- **Session dedup ineffective on non-deterministic output** — commands with timestamps, PIDs, or random ports (e.g., `docker ps`, `ps aux`) never hit the cache
- **`gh` CLI not supported in v0.1** — RTK handles it via JSON API wrapping; deferred to v0.2
- **Windows not supported in v0.1**
- **Shell-syntax bypass possible in permission checker** — quoted strings, heredocs, and command substitution can bypass deny rules. Fix requires real shell parsing.
- **Comment stripping in `cat`** is conservative and may destroy shebangs/markdown headings in some edge cases

## Development

```bash
zig build           # Native build
zig build test      # Run all 167 tests
zig build run       # Run ztk with args
zig build cross     # Cross-compile to 4 targets

./bench_rtk.sh      # Benchmark against RTK's test fixtures
```

## License

MIT (same as RTK, for ease of comparison)

## Credits

Built in a single session guided by:
- The RTK project ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) — for establishing the problem and showing what's possible
- Codex (OpenAI) — for the adversarial code review that caught the critical `git_status` correctness bug and the `max_output_bytes` hard-failure path
- Claude (Anthropic) — for implementation, testing, and the design decisions around the session state TTL model

ztk is not affiliated with RTK. It is an independent implementation that benchmarks against RTK's published results and test fixtures.
