///| WASM plugin execution types

///|
/// Result of WASM plugin execution
pub struct WasmExecResult {
  exit_code : Int
  stdout : Bytes
  stderr : Bytes
}

///|
/// Create a successful result with stdout
pub fn WasmExecResult::ok(stdout : Bytes) -> WasmExecResult {
  { exit_code: 0, stdout, stderr: Bytes::new(0) }
}

///|
/// Create a failed result with stderr
pub fn WasmExecResult::error(exit_code : Int, stderr : Bytes) -> WasmExecResult {
  { exit_code, stdout: Bytes::new(0), stderr }
}

///|
/// Errors that can occur during WASM execution
pub suberror WasmError {
  NotFound(String)
  ExecutionFailed(String)
  InvalidModule(String)
  Unsupported(String)
}

///|
/// Plugin convention type
pub enum PluginConvention {
  /// Extism-style: exports "transform(input) -> output"
  Simple
  /// WASI CLI: exports "_start", uses stdin/stdout
  WasiCli
}
