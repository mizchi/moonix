///|
/// StdStreamHandler adapter over `WasiCliHost` contract.
pub struct WasiStreamHandler {
  host : &WasiCliHost
}

///|
pub fn WasiStreamHandler::new(host : &WasiCliHost) -> WasiStreamHandler {
  { host, }
}

///|
pub impl @posix.StdStreamHandler for WasiStreamHandler with read(
  self,
  stream,
  len,
) {
  match stream {
    @posix.Stdin => self.host.read_stdin(len)
    @posix.Stdout | @posix.Stderr => b""
  }
}

///|
pub impl @posix.StdStreamHandler for WasiStreamHandler with write(
  self,
  stream,
  data,
) {
  match stream {
    @posix.Stdout => self.host.write_stdout(data)
    @posix.Stderr => self.host.write_stderr(data)
    @posix.Stdin => 0
  }
}
