# BitFS Plan (Git-Optimized Virtual FS)

## Goal

Provide a Git-optimized virtual filesystem in `mizchi/bit/x/fs` that can back Moonix via a thin adapter. The backend should prioritize fast snapshots, efficient reads, and scalable large repositories with partial clone support.

## Scope

This plan targets the `mizchi/bit/x/fs` package and its storage backends. Moonix only provides an adapter that maps its `FileSystemBackend` trait to the bitfs API.

## Constraints

- Keep API compatibility with `mizchi/bit` object model and `RepoFileSystem` / `FileSystem` traits.
- Support local-only mode and promisor-enabled mode.
- Avoid WASI-only assumptions in bitfs. WASI bindings live in Moonix adapters.
- Keep the on-disk git layout compatible with standard Git tooling.

## Current Building Blocks (Already In bitfs)

- Working layer with overlays and deletes.
- Lazy object loading and object cache (LRU).
- Partial clone support via promisor DB.
- BFS and glob-based prefetch utilities.

## Target Backend Interfaces

- `RepoFileSystem` for read access to `.git` object storage.
- `FileSystem` for write access to working changes and new objects.
- Optional async read and prefetch operations for promisor remotes.

## Adapter Strategy (Moonix)

- Implement `FileSystemBackend` by delegating to `bitfs.Fs` and a `RepoFileSystem` instance.
- Provide strict path normalization and error mapping to Moonix `FsError`.
- Limit adapter to `native` target because `bit/x/fs` is currently native-only.

## Optimization Plan

### Phase 1: Correctness and Minimal Semantics

1. Implement adapter tests for read, write, mkdir, rm_rf, rename, and stat.
2. Validate directory handling for root, empty dirs, and not-found cases.
3. Ensure error mapping is deterministic and stable across operations.

### Phase 2: Fast Read Path

1. Improve object cache hit rate by caching path resolutions and tree entries.
2. Keep a shallow directory index for `readdir` hot paths.
3. Add cheap existence checks for working-layer files before tree lookup.

### Phase 3: Partial Clone and Prefetch

1. Define prefetch strategies for hot paths: BFS, glob, and explicit file lists.
2. Expose a progress-friendly list of pending fetch paths.
3. Add tests for lazy fetch behavior and cache invalidation after fetch.

### Phase 4: Git Index Acceleration

1. Prefer using pack index and multi-pack index when available.
2. Cache tree parsing results and invalidate per tree ID.
3. Optional bitmap support for reachability queries used by large repos.

### Phase 5: Snapshot Scaling

1. Optimize snapshot creation by batching tree builders.
2. Minimize file writes for unchanged blobs.
3. Provide metrics hooks for snapshot timing and object counts.

## Test Strategy

- Blackbox tests for FileSystem behavior (read/write/dir ops).
- Integration tests covering snapshot/rollback and partial clone.
- Perf tests for large trees and repeated reads.

## Open Questions

- Required semantics for symlinks and executable bits.
- Concurrency model for overlapping read/write operations.
- Expected behavior for rename of directories and cross-layer deletes.

## Milestones

1. Adapter shipped in Moonix with native-only target.
2. Stable read/write semantics with error parity to MemFs where possible.
3. Partial clone workflow validated with async fetch.
4. Performance targets documented with reproducible benchmarks.
