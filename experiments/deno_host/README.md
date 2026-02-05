# deno_host - Deno で WASIp2 コンポーネントを仮想環境で実行

jco で WASIp2 コンポーネントを ES module に変換し、Deno 上で in-memory 仮想 FS/IO/CLI を注入して実行する。
`@bytecodealliance/preview2-shim` に依存せず、全 WASI インターフェースを自前実装にリマップする。

## アーキテクチャ

```
WASIp2 Component (.wasm)
  │
  │  wasm-tools component new --adapt
  ▼
WASIp2 Component (.wasm)
  │
  │  jco transpile --instantiation async --map (全インターフェース)
  ▼
ES module (instantiate 関数 + core.wasm)
  │
  │  Deno から import して instantiate() 呼び出し
  ▼
Deno runtime
  ├── virtual_io.ts     InputStream / OutputStream / IoError
  ├── virtual_fs.ts     仮想 FS (FileData tree)
  └── virtual_cli.ts    stdin/stdout/stderr/exit/environment/terminal
```

## モジュール構成

| ファイル | 役割 |
|---|---|
| `virtual_io.ts` | InputStream/OutputStream (handler ベース) + IoError |
| `virtual_fs.ts` | in-memory FS。Descriptor, DirectoryEntryStream, preopens |
| `virtual_cli.ts` | stdin/stdout/stderr キャプチャ、exit, environment, terminal スタブ |
| `component_test.ts` | E2E テスト (3 テスト) |
| `virtual_fs_test.ts` | FS ユニットテスト (20 テスト) |
| `fixtures/` | テスト用 Rust WASI コンポーネント + jco 出力 |

## ビルドパイプライン

```bash
# 1. Rust → wasm32-wasip1
cd fixtures
cargo build --target wasm32-wasip1 --release

# 2. WASI preview1 → WASIp2 component
wasm-tools component new target/wasm32-wasip1/release/wasi-test.wasm \
  --adapt wasi_snapshot_preview1.command.wasm -o component.wasm

# 3. jco transpile (全インターフェースを --map でリマップ)
jco transpile component.wasm -o out --instantiation async \
  --map 'wasi:filesystem/types@0.2.3=../../virtual_fs.ts#types' \
  --map 'wasi:filesystem/preopens@0.2.3=../../virtual_fs.ts#preopens' \
  --map 'wasi:io/streams@0.2.3=../../virtual_io.ts#streams' \
  --map 'wasi:io/error@0.2.3=../../virtual_io.ts#error' \
  --map 'wasi:cli/stdin@0.2.3=../../virtual_cli.ts#stdin' \
  --map 'wasi:cli/stdout@0.2.3=../../virtual_cli.ts#stdout' \
  --map 'wasi:cli/stderr@0.2.3=../../virtual_cli.ts#stderr' \
  --map 'wasi:cli/exit@0.2.3=../../virtual_cli.ts#exit' \
  --map 'wasi:cli/environment@0.2.3=../../virtual_cli.ts#environment' \
  --map 'wasi:cli/terminal-input@0.2.3=../../virtual_cli.ts#terminalInput' \
  --map 'wasi:cli/terminal-output@0.2.3=../../virtual_cli.ts#terminalOutput' \
  --map 'wasi:cli/terminal-stdin@0.2.3=../../virtual_cli.ts#terminalStdin' \
  --map 'wasi:cli/terminal-stdout@0.2.3=../../virtual_cli.ts#terminalStdout' \
  --map 'wasi:cli/terminal-stderr@0.2.3=../../virtual_cli.ts#terminalStderr'

# または deno task で一括実行
deno task build-fixture
```

## 使い方

```typescript
import { _setFileData, _getFileData, preopens, types } from "./virtual_fs.ts";
import { streams, error } from "./virtual_io.ts";
import * as cli from "./virtual_cli.ts";
import { instantiate } from "./fixtures/out/component.js";

// 1. 仮想 FS セットアップ
_setFileData({
  dir: {
    "input.txt": { source: "Hello from Deno" },
  },
});

// 2. core wasm ローダー
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const bytes = await Deno.readFile(new URL(`./fixtures/out/${path}`, import.meta.url));
  return WebAssembly.compile(bytes);
}

// 3. インスタンス生成（imports キーはマップ先パス）
const component = await instantiate(getCoreModule, {
  "../../virtual_cli.ts": {
    environment: cli.environment,
    exit: cli.exit,
    stderr: cli.stderr,
    stdin: cli.stdin,
    stdout: cli.stdout,
    terminalInput: cli.terminalInput,
    terminalOutput: cli.terminalOutput,
    terminalStderr: cli.terminalStderr,
    terminalStdin: cli.terminalStdin,
    terminalStdout: cli.terminalStdout,
  },
  "../../virtual_fs.ts": { preopens, types },
  "../../virtual_io.ts": { streams, error },
});

// 4. 実行
component.run.run();

// 5. 結果回収
const fileData = _getFileData();
const stdout = cli._getStdout();
```

## FileData 構造

```typescript
// ディレクトリ
{ dir: { "name": FileDataEntry, ... } }

// ファイル
{ source: Uint8Array | string }
```

## テスト

```bash
deno task test
# または
deno test --no-check --allow-read --allow-env
```

- `virtual_fs_test.ts`: 20 テスト (read, write, stream, directory, preopen, ネスト)
- `component_test.ts`: 3 テスト (正常実行, エラー時の挙動, 異なる入力)

## 設計上の注意点

### Deno + preview2-shim の非互換

Deno の npm 互換レイヤーは `node` condition を使う（`browser` ではない）。
`@bytecodealliance/preview2-shim` の `node` 版は `worker-io.js` を使い、
内部 stream ID ベースの InputStream/OutputStream を生成する。
handler ベースのコンストラクタ（browser 版の API）は動かない。

jco トランスパイル済みコードは `instanceof InputStream` チェックを行うため、
preview2-shim と自前実装を混在させるとリソース検証エラーになる。

**解決策**: `--map` で全 WASI インターフェースを自前実装にリマップし、
preview2-shim への依存を完全に排除する。

### --instantiation async

`--instantiation async` を使うことで、`instantiate()` を呼ぶたびに
新しい wasm インスタンスが生成される。テストで複数回実行する場合に必要。
`--map` と併用した場合、imports オブジェクトのキーはマップ先のパス
（例: `../../virtual_cli.ts`）になる。
