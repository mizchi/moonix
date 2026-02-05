# experiments 進捗メモ

## 構成

| ディレクトリ | ランタイム | 役割 |
|---|---|---|
| `wasmtime_host/` | Rust (wasmtime) | WASIp2/p3 ホスト、MemFs、決定論的カーネル |
| `deno_host/` | Deno (jco) | WASIp2 コンポーネントを仮想 FS/IO/CLI 付きで Deno 実行 |

## 進捗

### wasmtime_host (Rust)
- WASIp2 / WASIp3 の Linker 構築
- 決定論的な `clock` / `random` をホスト側で差し替え
- `socket_addr_check` でネットワークを全拒否
- **in-memory FS (MemFs)** を Rust に移植、WASI preopened_dir として提供
- MemFs ↔ tempdir ブリッジ (FsBridge) で materialize/snapshot
- `cargo test` で 33 テスト全パス

### deno_host (Deno + jco)
- WASIp2 コンポーネントを jco transpile → ES module
- `virtual_io.ts`: InputStream/OutputStream (handler ベース) + IoError
- `virtual_fs.ts`: in-memory FS (FileData tree)、virtual_io.ts の stream を使用
- `virtual_cli.ts`: stdin/stdout/stderr キャプチャ、exit、environment、terminal スタブ
- `--map` + `--instantiation async` で全 WASI インターフェースを自前実装にリマップ
- preview2-shim 依存なし（Deno の `node` condition 問題を回避）
- Rust テストフィクスチャ (wasm32-wasip1 → wasm-tools component → jco transpile) で E2E 検証
- `deno test` で 23 テスト全パス (virtual_fs 20 + component E2E 3)

## TODO

- wasmtime_host: `wasi:sockets` 完全拒否、`wasi:http` モック
- wasmtime_host: MemFs を Host trait 直接実装に差し替え（tempdir 不要化）
- deno_host: MoonBit コンポーネントでの E2E 検証
- MoonBit 側の WIT/world 仕様の確定
