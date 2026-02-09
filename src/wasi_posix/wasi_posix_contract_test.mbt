///|
struct FakeFsHost {
  inner : @fs.MemFs
}

///|
fn FakeFsHost::new() -> FakeFsHost {
  { inner: @fs.MemFs::new() }
}

///|
fn to_node_type(ft : @fs.FileType) -> WasiNodeType {
  match ft {
    @fs.FileType::File => WasiNodeType::File
    @fs.FileType::Directory => WasiNodeType::Directory
    @fs.FileType::Symlink => WasiNodeType::Symlink
  }
}

///|
pub impl WasiFsHost for FakeFsHost with read_file(self, path) {
  @fs.FileSystemBackend::read_file(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with exists(self, path) {
  @fs.FileSystemBackend::exists(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with stat(self, path) {
  let s = @fs.FileSystemBackend::stat(self.inner, path)
  { node_type: to_node_type(s.file_type), size: s.size }
}

///|
pub impl WasiFsHost for FakeFsHost with readdir(self, path) {
  @fs.FileSystemBackend::readdir(self.inner, path).map(fn(e) {
    { name: e.name, node_type: to_node_type(e.file_type) }
  })
}

///|
pub impl WasiFsHost for FakeFsHost with write_file(self, path, data) {
  @fs.FileSystemBackend::write_file(self.inner, path, data)
}

///|
pub impl WasiFsHost for FakeFsHost with mkdir(self, path) {
  @fs.FileSystemBackend::mkdir(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with mkdir_p(self, path) {
  @fs.FileSystemBackend::mkdir_p(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with remove(self, path) {
  @fs.FileSystemBackend::remove(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with rmdir(self, path) {
  @fs.FileSystemBackend::rmdir(self.inner, path)
}

///|
pub impl WasiFsHost for FakeFsHost with rename(self, old_path, new_path) {
  @fs.FileSystemBackend::rename(self.inner, old_path, new_path)
}

///|
test "WasiFs adapter delegates to host contract" {
  let host = FakeFsHost::new()
  let fs = WasiFs::new(host)
  @fs.FileSystemBackend::mkdir_p(fs, "/tmp/a")
  @fs.FileSystemBackend::write_string(fs, "/tmp/a/hello.txt", "hello")
  assert_true(@fs.FileSystemBackend::exists(fs, "/tmp/a/hello.txt"))
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/tmp/a/hello.txt"), "hello")
  let entries = @fs.FileSystemBackend::readdir(fs, "/tmp/a")
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].name, "hello.txt")
}

///|
struct FakeCliHost {
  stdin : Bytes
  mut stdin_pos : Int
  mut stdout : Bytes
  mut stderr : Bytes
}

///|
fn FakeCliHost::new(input : Bytes) -> FakeCliHost {
  { stdin: input, stdin_pos: 0, stdout: b"", stderr: b"" }
}

///|
fn FakeCliHost::stdout(self : FakeCliHost) -> Bytes {
  self.stdout
}

///|
fn FakeCliHost::stderr(self : FakeCliHost) -> Bytes {
  self.stderr
}

///|
pub impl WasiCliHost for FakeCliHost with read_stdin(self, len) {
  let available = self.stdin.length() - self.stdin_pos
  let to_read = if len < available { len } else { available }
  if to_read <= 0 {
    return b""
  }
  let out = Bytes::makei(to_read, fn(i) { self.stdin[self.stdin_pos + i] })
  self.stdin_pos += to_read
  out
}

///|
pub impl WasiCliHost for FakeCliHost with write_stdout(self, data) {
  self.stdout = self.stdout + data
  data.length()
}

///|
pub impl WasiCliHost for FakeCliHost with write_stderr(self, data) {
  self.stderr = self.stderr + data
  data.length()
}

///|
test "WasiStreamHandler delegates to host contract" {
  let host = FakeCliHost::new(b"abc")
  let streams = WasiStreamHandler::new(host)
  let r = @posix.StdStreamHandler::read(streams, @posix.Stdin, 2)
  assert_eq(r, b"ab")
  let n1 = @posix.StdStreamHandler::write(streams, @posix.Stdout, b"out")
  let n2 = @posix.StdStreamHandler::write(streams, @posix.Stderr, b"err")
  assert_eq(n1, 3)
  assert_eq(n2, 3)
  assert_eq(host.stdout(), b"out")
  assert_eq(host.stderr(), b"err")
}
