///| Backward-compatible facade for Preview2 WASI stdio adapter.

///|

///|
/// New code should prefer `@wasi_posix`.
pub struct WasiStreamHandler {
  inner : @wasi_posix.WasiStreamHandler
}

///|
pub fn WasiStreamHandler::new() -> WasiStreamHandler {
  { inner: @wasi_posix.WasiStreamHandler::from_p2() }
}

///|
pub impl @posix.StdStreamHandler for WasiStreamHandler with read(
  self,
  stream,
  len,
) {
  @posix.StdStreamHandler::read(self.inner, stream, len)
}

///|
pub impl @posix.StdStreamHandler for WasiStreamHandler with write(
  self,
  stream,
  data,
) {
  @posix.StdStreamHandler::write(self.inner, stream, data)
}
