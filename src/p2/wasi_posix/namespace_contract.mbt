///| Compile-time namespace contract:

///|
/// `src/p2/wasi_posix` must expose preview2 factories with these signatures.
let _p2_fs_factory_contract : (@wasi_fs.Descriptor) -> @wasi_posix_core.WasiFs = new_fs

///|
let _p2_stream_factory_contract : () -> @wasi_posix_core.WasiStreamHandler = new_stream_handler
