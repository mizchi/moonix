# wasi_posix moved

WASI host bridge contracts were extracted from `moonix` to `mizchi/wasi_posix`.

- repository: https://github.com/mizchi/wasi_posix
- packages: `@p2`, `@p3`
- role: contract-only (`pub(open) trait` and contract types)

`moonix` keeps core runtime contracts (`@fs`, `@posix`) and primitives.
Concrete WASI injection/provider/adapter implementations are expected to live in separate implementation modules that depend on `mizchi/wasi_posix`.
