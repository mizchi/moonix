///| Preview-agnostic contract layer for WASI-backed POSIX adapters.

///|

///| p2 and p3 differ at the low-level API surface:

///| - filesystem: sync tuple/list APIs vs async stream/future APIs

///| - stdio: io/streams handles vs stream<u8>/future

///|

///|
/// These contracts keep `@fs` and `@posix` independent from preview details.
pub(all) enum WasiNodeType {
  File
  Directory
  Symlink
  Other
} derive(Show, Eq)

///|
pub(all) struct WasiNodeStat {
  node_type : WasiNodeType
  size : Int
} derive(Show, Eq)

///|
pub(all) struct WasiDirEntry {
  name : String
  node_type : WasiNodeType
} derive(Show, Eq)

///|
/// Host contract for filesystem operations used by `WasiFs`.
pub(open) trait WasiFsHost {
  read_file(Self, String) -> Bytes raise @fs.FsError
  exists(Self, String) -> Bool
  stat(Self, String) -> WasiNodeStat raise @fs.FsError
  readdir(Self, String) -> Array[WasiDirEntry] raise @fs.FsError
  write_file(Self, String, Bytes) -> Unit raise @fs.FsError
  mkdir(Self, String) -> Unit raise @fs.FsError
  mkdir_p(Self, String) -> Unit raise @fs.FsError
  remove(Self, String) -> Unit raise @fs.FsError
  rmdir(Self, String) -> Unit raise @fs.FsError
  rename(Self, String, String) -> Unit raise @fs.FsError
}

///|
/// Host contract for stdin/stdout/stderr used by `WasiStreamHandler`.
pub(open) trait WasiCliHost {
  read_stdin(Self, Int) -> Bytes
  write_stdout(Self, Bytes) -> Int
  write_stderr(Self, Bytes) -> Int
}
