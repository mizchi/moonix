# TODO (MoonBit 0.8 対応メモ)

最終更新: 2026-02-11

## 背景

- 依存更新を試行:
  - `mizchi/bit: 0.10.0 -> 0.16.0`
  - `mizchi/cst: 0.1.0 -> 0.1.4`
  - `mizchi/ripple: 0.1.0 -> 0.1.2`
  - `moonbitlang/x: 0.4.38 -> 0.4.40`
  - `mizchi/wasi_interface: 0.2.0 -> 0.2.1`
- `moon check --target wasm-gc` で `p3_memory` 由来のエラーが 43 件発生。
- 主因は `mizchi/wasi_interface/p3` 側の API/型表現変更への未追従。

## ブロッカー

- 旧コンストラクタ呼び出しが未対応:
  - 例: `@p3.ClocksTypesDuration(...)`, `@p3.HttpTypesFieldValue(...)`
- 旧 tuple 風アクセス (`.0`) が未対応:
  - 例: `name.0`, `headers.0`, `size.0`

## 追加調査メモ (2026-02-11)

- `p3_memory` は `moon check` は通るが、`moon test --target wasm-gc` で落ちる。
- 典型エラー:
  - `struct.new[...] expected type anyref, found i64.const`
  - `expected (ref ...), got anyref`
- 原因見立て:
  - `mizchi/wasi_interface/p3` の `type`（opaque）を `"%identity"` で数値と相互変換しており、
    wasm-gc 実行時の実体表現（`anyref`）と不整合。
- 実験したが未解決:
  - `%identity` での直接キャスト
  - Box struct 経由キャスト
  - 逆変換を避ける実装への退避
- 必要な対応:
  - `wasi_interface/p3` 側で opaque `type` の `lift/lower`（または同等の公開API）を提供し、
    `moonix` 側はそれを使って変換する。

## 対応タスク

1. `p3_memory` のコンストラクタ呼び出しを新 API へ移行する
   - 対象:
     - `src/p3_memory/clocks_adapter.mbt`
     - `src/p3_memory/fs_adapter.mbt`
     - `src/p3_memory/http_adapter.mbt`
     - `src/p3_memory/tests.mbt`
2. `p3_memory` の `.0` 参照を新しい accessor/unwrap 方式へ置換する
   - 対象:
     - `src/p3_memory/fs_adapter.mbt`
     - `src/p3_memory/http_adapter.mbt`
     - `src/p3_memory/tests.mbt`
3. 置換後に `p3_memory` テストを修正する
   - `src/p3_memory/tests.mbt`
4. 依存更新は一括ではなく段階的に行う
   - `moon add <dep>` を1件ずつ実行して都度 `moon check --target wasm-gc` を確認
   - まず `mizchi/wasi_interface` の追従完了を優先

## 再現・調査コマンド

```sh
moon check --target wasm-gc
rg -n "@p3\\.[A-Za-z0-9_]+\\(" src/p3_memory
rg -n "\\.0\\b" src/p3_memory
```

## 完了条件

- `moon fmt`
- `moon check --target wasm-gc` がエラー 0
- `moon info --target wasm-gc`
- 変更差分を commit/push
