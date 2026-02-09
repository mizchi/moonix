///| WASM Runner trait - implemented by host environment

///|
/// Context for WASM execution
pub struct WasmExecContext {
  /// Input bytes (stdin or function input)
  stdin : Bytes
  /// Command-line arguments
  args : Array[String]
  /// Environment variables
  env : Array[(String, String)]
  /// Working directory
  cwd : String
}

///|
/// Create execution context
pub fn WasmExecContext::new(
  stdin : Bytes,
  args : Array[String],
  env : Array[(String, String)],
  cwd : String,
) -> WasmExecContext {
  { stdin, args, env, cwd }
}

///|
/// WASM Runner trait
/// Host environment (browser, Deno, etc.) implements this
pub(open) trait WasmRunner {
  /// Execute a WASM module
  /// - wasm_bytes: The compiled WASM binary
  /// - ctx: Execution context (stdin, args, env)
  /// Returns execution result or error
  run(Self, wasm_bytes : Bytes, ctx : WasmExecContext) -> WasmExecResult raise WasmError
}

///|
/// Stub runner that always returns an error
/// Used when no WASM runtime is available
pub struct StubWasmRunner {
  _placeholder : Int
}

///|
pub fn StubWasmRunner::new() -> StubWasmRunner {
  { _placeholder: 0 }
}

///|
pub impl WasmRunner for StubWasmRunner with run(_self, _wasm_bytes, _ctx) {
  raise WasmError::Unsupported("No WASM runtime available")
}
