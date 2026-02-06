# wasmtime host experiments (WASIp2 / WASIp3)

MoonBit で生成したコンポーネントを wasmtime 上で動かす前提で、
WASIp2 / WASIp3 のホスト差し替えポイントを検証するための骨格。

## アーキテクチャ

```
MemFs (in-memory, inode-based)
  │
  ├── walk() で全エントリを列挙
  │
FsBridge
  ├── materialize()  MemFs → tempdir に書き出し
  ├── snapshot()     tempdir → MemFs に読み戻し
  │
P2State / P3State
  ├── build_state(seed, Option<MemFs>)
  │     MemFs があれば materialize → preopened_dir("/")
  ├── snapshot_fs()  実行後に FS を読み戻し
  └── take_fs()      FsBridge を取り出して MemFs を回収
```

## モジュール構成

| ファイル | 役割 |
|---|---|
| `src/memfs.rs` | MoonBit MemFs の Rust 移植。inode ベース、wasmtime-wasi 非依存 |
| `src/fs_bridge.rs` | MemFs ↔ tempdir ブリッジ |
| `src/p2.rs` | WASIp2 ホスト状態 (`P2State`) |
| `src/p3.rs` | WASIp3 ホスト状態 (`P3State`) |
| `src/virtual_kernel.rs` | 決定論的クロック・RNG |

## できていること

- WASIp2 / WASIp3 の `Linker` を構築できる
- 仮想クロック / 決定論的 RNG をホスト側に差し込む
- ネットワークは全拒否（`socket_addr_check` で拒否）
- **in-memory FS (MemFs)** を WASI ゲストに preopened_dir として提供
- 実行後に tempdir → MemFs への snapshot で変更を回収可能
- MemFs は wasmtime-wasi に依存しない独立モジュール

## 使い方

```rust
use wasmtime_host_experiments::memfs::MemFs;
use wasmtime_host_experiments::p2;

let mut fs = MemFs::new();
fs.mkdir_p("/src").unwrap();
fs.write_string("/src/main.rs", "fn main() {}").unwrap();

// FS 付きで P2State を構築（materialize → preopened_dir）
let mut state = p2::build_state(42, Some(fs)).unwrap();

// ... WASM コンポーネント実行 ...

// 実行後の FS 変更を回収
state.snapshot_fs().unwrap();
let bridge = state.take_fs().unwrap();
let updated_fs = bridge.into_memfs();
```

## テスト

```
cargo test
```

- `memfs_test`: 17 テスト (基本操作, パス正規化, mkdir_p, remove/rmdir, copy, rm_rf, walk, エラー)
- `fs_bridge_test`: 8 テスト (materialize, roundtrip, 変更/追加/削除の検知)
- `virtual_kernel_test`: 8 テスト (クロック/RNG 決定論, linker 構築, FS 統合)

## まだやること

- `wasi:sockets` を完全拒否で実装する
- `wasi:http` をモックで実装する
- MemFs を Host trait 直接実装に差し替え（tempdir 不要化）
- MoonBit 側の WIT/world 仕様の確定

## 将来の Host trait 化パス

MemFs モジュールは wasmtime-wasi に依存しない設計。
FsBridge を Host trait 実装に差し替えるだけで、MemFs 本体とテストはそのまま使える。
