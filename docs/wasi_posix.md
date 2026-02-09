# wasi_posix layering

`@wasi_posix` separates moonix core contracts (`@fs`, `@posix`) from WASI preview-specific details.

## Layering

1. `WasiFsHost` / `WasiCliHost` (`src/wasi_posix/contracts.mbt`)
2. `WasiFs` / `WasiStreamHandler` adapters (`src/wasi_posix/fs_adapter.mbt`, `src/wasi_posix/cli_adapter.mbt`)
3. Preview2 hosts (`src/wasi_posix/p2_fs_host.mbt`, `src/wasi_posix/p2_cli_host.mbt`)

`@wasi` remains as a backward-compatible facade.

## Why this boundary

WASI preview2 and preview3 differ in the low-level API shape.

- Filesystem
  - p2: direct `read/write` list-based APIs and mostly sync calls.
  - p3 draft: stream/future-based I/O and `async` filesystem calls.
- CLI stdio
  - p2: `get-stdin/get-stdout/get-stderr` + `wasi:io/streams`.
  - p3 draft: `read-via-stream` / `write-via-stream` returning streams and futures.
- Clocks used by filesystem metadata
  - p2 uses `wasi:clocks/wall-clock`.
  - p3 draft uses `wasi:clocks/system-clock`.

The contract layer keeps these changes local to host implementations.

## Preview3 migration plan

1. Add `WasiPreview3FsHost` implementing `WasiFsHost`.
2. Add `WasiPreview3CliHost` implementing `WasiCliHost`.
3. Add `WasiFs::from_p3(...)` and `WasiStreamHandler::from_p3(...)`.
4. Keep `WasiFs` / `WasiStreamHandler` adapters unchanged.
