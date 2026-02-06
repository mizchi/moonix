# moonix

> **WARNING: This library is highly experimental. APIs will change without notice. Do not use in production.**

Virtual POSIX layer for MoonBit — in-memory Unix-like filesystem, process emulation, and git-backed versioning, all running in WASM.

## What is this for?

moonix provides a sandboxed POSIX-like environment that runs entirely in-memory, targeting two primary use cases:

1. **AI sandbox**: A safe execution environment for AI-generated code. All filesystem operations are isolated in memory — nothing touches the host system. Combined with capability-based security, this makes it suitable for running untrusted code from LLM outputs.

2. **Git-backed virtual filesystem**: Using `@gitfs`, you get a virtual filesystem with automatic git versioning powered by [mizchi/bit](https://github.com/mizchi/bit). Every `snapshot()` creates a real git commit, and you can `rollback()`, `branch()`, and `switch()` — all in memory, no native git required.

```
┌─────────────────────────────────────────────┐
│  Your App / AI Agent                        │
├─────────────────────────────────────────────┤
│  @gitfs   - Git-versioned virtual FS        │
│  @fs      - Pluggable filesystem backend    │
│  @posix   - fd, env, cwd emulation          │
│  @proc    - Cooperative process scheduler   │
│  @net     - Virtual network / HTTP          │
│  @wasm    - WASM module execution           │
│  @capability - Permission control           │
├─────────────────────────────────────────────┤
│  MemFs (in-memory) or WasiFs (host bridge)  │
└─────────────────────────────────────────────┘
```

## Installation

```bash
moon add mizchi/moonix
```

## Example: Git-backed filesystem

```moonbit
// Create a git-versioned in-memory filesystem
let gfs = @gitfs.GitBackedFs::new(author="user <user@example.com>")

// Write files — just like a normal filesystem
gfs.write_file("/src/main.mbt", b"fn main { println(\"hello\") }")

// Snapshot creates a git commit internally
let snap = gfs.snapshot("initial commit")

// Modify and snapshot again
gfs.write_file("/src/main.mbt", b"fn main { println(\"world\") }")
let snap2 = gfs.snapshot("update message")

// Rollback to any previous snapshot
gfs.rollback(snap)

// Branch and switch
gfs.branch("feature")
gfs.switch("feature")
```

## Example: Virtual shell (currently disabled)

The shell module (`@shell`) with built-in commands is temporarily disabled while its dependency (`mizchi/xsh`) is being stabilized. It will be re-enabled in a future release.

## Packages

| Package | Description |
|---------|-------------|
| `@fs` | `FileSystemBackend` trait + `MemFs` (in-memory inode-based filesystem) |
| `@gitfs` | `GitBackedFs` — git-versioned filesystem using mizchi/bit |
| `@bitfs_adapter` | Adapter: bit's `x/fs` → moonix `FileSystemBackend` |
| `@posix` | POSIX emulation (file descriptors, env, cwd) |
| `@proc` | Cooperative process scheduler, signals, semaphores |
| `@net` | Virtual socket layer, HTTP parsing |
| `@wasm` | WASM module execution with capability control |
| `@capability` | Capability-based permission system |
| `@sh` | Shell parser and AST |
| `@wasi` | WASI host filesystem bridge |

## Related projects

- [mizchi/bit](https://github.com/mizchi/bit) — Pure MoonBit git implementation (used by `@gitfs`)
- [mizchi/wasi](https://github.com/mizchi/wasi.mbt) — WASIp2 bindings for MoonBit

## License

MIT
