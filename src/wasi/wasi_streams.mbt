///| Backward-compatible facade for Preview2 WASI stdio adapter.

///|

///|
/// New code should prefer `@wasi_posix`.
pub struct WasiStreamHandler {
  inner : @wasi_posix.WasiStreamHandler
}

///|
pub fn WasiStreamHandler::new() -> WasiStreamHandler {
  { inner: @p2_wasi_posix.new_stream_handler() }
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
