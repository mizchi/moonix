# wasi_posix moved

WASI host bridge packages were extracted from `moonix` to `mizchi/wasi_posix`.

- repository: https://github.com/mizchi/wasi_posix
- packages: `@wasi_posix`, `@p2/wasi_posix`, `@p3/wasi_posix`

`moonix` keeps core contracts (`@fs`, `@posix`) and runtime primitives, while preview-specific WASI providers live in the dedicated module.
