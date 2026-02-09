///| POSIX context - the main interface for POSIX operations

///|
/// Helper: copy bytes slice
fn bytes_slice(data : Bytes, start : Int, end : Int) -> Bytes {
  let len = end - start
  if len <= 0 {
    return b""
  }
  Bytes::makei(len, fn(i) { data[start + i] })
}

///|
/// Helper: concatenate bytes
fn bytes_concat(a : Bytes, b : Bytes) -> Bytes {
  a + b
}

///|
/// Open file handle
struct FileHandle {
  path : String
  flags : OpenFlags
  mut position : Int
}

///|
/// Standard stream type
pub(all) enum StdStream {
  Stdin
  Stdout
  Stderr
}

///|
/// Standard stream handler
pub(open) trait StdStreamHandler {
  read(Self, StdStream, Int) -> Bytes
  write(Self, StdStream, Bytes) -> Int
}

///|
/// Null stream handler (discards output, returns empty input)
pub struct NullStreamHandler {}

///|
pub fn NullStreamHandler::new() -> NullStreamHandler {
  NullStreamHandler::{  }
}

///|
pub impl StdStreamHandler for NullStreamHandler with read(_self, _stream, _len) {
  b""
}

///|
pub impl StdStreamHandler for NullStreamHandler with write(_self, _stream, data) {
  data.length()
}

///|
/// Buffered stream handler (stores output in memory)
pub struct BufferedStreamHandler {
  mut stdout : Bytes
  mut stderr : Bytes
  stdin : Bytes
  mut stdin_pos : Int
}

///|
pub fn BufferedStreamHandler::new() -> BufferedStreamHandler {
  { stdout: b"", stderr: b"", stdin: b"", stdin_pos: 0 }
}

///|
pub fn BufferedStreamHandler::with_stdin(
  input : Bytes,
) -> BufferedStreamHandler {
  { stdout: b"", stderr: b"", stdin: input, stdin_pos: 0 }
}

///|
pub fn BufferedStreamHandler::get_stdout(self : BufferedStreamHandler) -> Bytes {
  self.stdout
}

///|
pub fn BufferedStreamHandler::get_stderr(self : BufferedStreamHandler) -> Bytes {
  self.stderr
}

///|
pub impl StdStreamHandler for BufferedStreamHandler with read(self, stream, len) {
  match stream {
    Stdin => {
      let available = self.stdin.length() - self.stdin_pos
      let to_read = if len < available { len } else { available }
      if to_read <= 0 {
        return b""
      }
      let result = bytes_slice(
        self.stdin,
        self.stdin_pos,
        self.stdin_pos + to_read,
      )
      self.stdin_pos += to_read
      result
    }
    Stdout | Stderr => b"" // Cannot read from output streams
  }
}

///|
pub impl StdStreamHandler for BufferedStreamHandler with write(
  self,
  stream,
  data,
) {
  match stream {
    Stdin => 0 // Cannot write to input stream
    Stdout => {
      self.stdout = bytes_concat(self.stdout, data)
      data.length()
    }
    Stderr => {
      self.stderr = bytes_concat(self.stderr, data)
      data.length()
    }
  }
}

///|
/// POSIX context
pub struct PosixContext {
  fs : &@fs.FileSystemBackend
  streams : &StdStreamHandler
  mut cwd : String
  env : Map[String, String]
  fds : Map[Int, FileHandle]
  mut next_fd : Int
}

///|
/// Create a new POSIX context
pub fn PosixContext::new(
  fs : &@fs.FileSystemBackend,
  streams : &StdStreamHandler,
) -> PosixContext {
  let env : Map[String, String] = {}
  env.set("HOME", "/home")
  env.set("PATH", "/bin:/usr/bin")
  env.set("PWD", "/")
  { fs, streams, cwd: "/", env, fds: {}, next_fd: 3 } // 0, 1, 2 are reserved for stdin/stdout/stderr
}

///|
/// Get current working directory
pub fn PosixContext::getcwd(self : PosixContext) -> String {
  self.cwd
}

///|
/// Change current working directory
pub fn PosixContext::chdir(
  self : PosixContext,
  path : String,
) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)
  if not(self.fs.is_dir(abs_path)) {
    raise PosixError::ENOTDIR(path)
  }
  self.cwd = abs_path
  self.env.set("PWD", abs_path)
}

///|
/// Resolve relative path to absolute
pub fn PosixContext::resolve_path(self : PosixContext, path : String) -> String {
  if path.has_prefix("/") {
    @fs.normalize_path(path)
  } else {
    @fs.normalize_path(self.cwd + "/" + path)
  }
}

///|
/// Get environment variable
pub fn PosixContext::getenv(self : PosixContext, name : String) -> String? {
  self.env.get(name)
}

///|
/// Set environment variable
pub fn PosixContext::setenv(
  self : PosixContext,
  name : String,
  value : String,
) -> Unit {
  self.env.set(name, value)
}

///|
/// Unset environment variable
pub fn PosixContext::unsetenv(self : PosixContext, name : String) -> Unit {
  self.env.remove(name)
}

///|
/// Get all environment variables
pub fn PosixContext::get_all_env(
  self : PosixContext,
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for k, v in self.env {
    result.push((k, v))
  }
  result
}

///|
/// Open a file
pub fn PosixContext::open(
  self : PosixContext,
  path : String,
  flags : OpenFlags,
) -> Int raise PosixError {
  let abs_path = self.resolve_path(path)

  // Check if file exists
  if not(self.fs.exists(abs_path)) {
    if flags.create {
      // Create empty file
      self.fs.write_file(abs_path, b"") catch {
        e => raise fs_error_to_posix(e)
      }
    } else {
      raise PosixError::ENOENT(path)
    }
  }

  // Check if it's a file
  if self.fs.is_dir(abs_path) {
    raise PosixError::EISDIR(path)
  }

  // Truncate if requested
  if flags.truncate && flags.write {
    self.fs.write_file(abs_path, b"") catch {
      e => raise fs_error_to_posix(e)
    }
  }

  // Allocate file descriptor
  let fd = self.next_fd
  self.next_fd += 1
  let handle = FileHandle::{ path: abs_path, flags, position: 0 }

  // Set position to end if append mode
  if flags.append {
    let stat = self.fs.stat(abs_path) catch { e => raise fs_error_to_posix(e) }
    handle.position = stat.size
  }
  self.fds.set(fd, handle)
  fd
}

///|
/// Close a file
pub fn PosixContext::close(
  self : PosixContext,
  fd : Int,
) -> Unit raise PosixError {
  if fd < 3 {
    // Cannot close standard streams
    return
  }
  if not(self.fds.contains(fd)) {
    raise PosixError::EBADF("invalid fd: " + fd.to_string())
  }
  self.fds.remove(fd)
}

///|
/// Read from file descriptor
pub fn PosixContext::read(
  self : PosixContext,
  fd : Int,
  len : Int,
) -> Bytes raise PosixError {
  // Handle standard streams
  if fd == STDIN_FD {
    return self.streams.read(StdStream::Stdin, len)
  }
  if fd == STDOUT_FD || fd == STDERR_FD {
    return b"" // Cannot read from output streams
  }
  let handle = match self.fds.get(fd) {
    None => raise PosixError::EBADF("invalid fd: " + fd.to_string())
    Some(h) => h
  }
  if not(handle.flags.read) {
    raise PosixError::EBADF("fd not open for reading")
  }
  let data = self.fs.read_file(handle.path) catch {
    e => raise fs_error_to_posix(e)
  }
  let available = data.length() - handle.position
  let to_read = if len < available { len } else { available }
  if to_read <= 0 {
    return b""
  }
  let result = bytes_slice(data, handle.position, handle.position + to_read)
  handle.position += to_read
  result
}

///|
/// Write to file descriptor
pub fn PosixContext::write(
  self : PosixContext,
  fd : Int,
  data : Bytes,
) -> Int raise PosixError {
  // Handle standard streams
  if fd == STDOUT_FD {
    return self.streams.write(StdStream::Stdout, data)
  }
  if fd == STDERR_FD {
    return self.streams.write(StdStream::Stderr, data)
  }
  if fd == STDIN_FD {
    return 0 // Cannot write to stdin
  }
  let handle = match self.fds.get(fd) {
    None => raise PosixError::EBADF("invalid fd: " + fd.to_string())
    Some(h) => h
  }
  if not(handle.flags.write) {
    raise PosixError::EBADF("fd not open for writing")
  }
  let current = self.fs.read_file(handle.path) catch { _ => b"" }

  // Build new content
  let new_data = if handle.position >= current.length() {
    // Append or extend
    let padding_len = handle.position - current.length()
    let padding = Bytes::make(padding_len, b'\x00')
    bytes_concat(bytes_concat(current, padding), data)
  } else {
    // Overwrite in the middle
    let before = bytes_slice(current, 0, handle.position)
    let after_start = handle.position + data.length()
    let after = if after_start < current.length() {
      bytes_slice(current, after_start, current.length())
    } else {
      b""
    }
    bytes_concat(bytes_concat(before, data), after)
  }
  self.fs.write_file(handle.path, new_data) catch {
    e => raise fs_error_to_posix(e)
  }
  handle.position += data.length()
  data.length()
}

///|
/// Seek in file
pub fn PosixContext::lseek(
  self : PosixContext,
  fd : Int,
  offset : Int,
  whence : Int, // 0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END
) -> Int raise PosixError {
  if fd < 3 {
    raise PosixError::EINVAL("cannot seek on standard streams")
  }
  let handle = match self.fds.get(fd) {
    None => raise PosixError::EBADF("invalid fd")
    Some(h) => h
  }
  let stat = self.fs.stat(handle.path) catch { e => raise fs_error_to_posix(e) }
  let new_pos = match whence {
    0 => offset // SEEK_SET
    1 => handle.position + offset // SEEK_CUR
    2 => stat.size + offset // SEEK_END
    _ => raise PosixError::EINVAL("invalid whence")
  }
  if new_pos < 0 {
    raise PosixError::EINVAL("negative position")
  }
  handle.position = new_pos
  new_pos
}
