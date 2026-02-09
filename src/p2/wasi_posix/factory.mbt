///|
/// Preview2 constructors for shared `@wasi_posix` adapters.
pub fn new_fs(root : @wasi_fs.Descriptor) -> @wasi_posix_core.WasiFs {
  let host = WasiPreview2FsHost::new(root)
  @wasi_posix_core.WasiFs::new(host)
}

///|
pub fn new_stream_handler() -> @wasi_posix_core.WasiStreamHandler {
  let host = WasiPreview2CliHost::new()
  @wasi_posix_core.WasiStreamHandler::new(host)
}
