test "PosixContext basic operations" {
  let fs = @fs.MemFs::new()
  let streams = BufferedStreamHandler::new()
  let ctx = PosixContext::new(fs, streams)

  // Initial state
  assert_eq(ctx.getcwd(), "/")
  assert_eq(ctx.getenv("HOME"), Some("/home"))
  assert_eq(ctx.getenv("PWD"), Some("/"))

  // Create directory
  fs.mkdir("/home")

  // chdir
  ctx.chdir("/home")
  assert_eq(ctx.getcwd(), "/home")
  assert_eq(ctx.getenv("PWD"), Some("/home"))

  // setenv/unsetenv
  ctx.setenv("FOO", "bar")
  assert_eq(ctx.getenv("FOO"), Some("bar"))
  ctx.unsetenv("FOO")
  assert_eq(ctx.getenv("FOO"), None)
}

test "PosixContext file operations" {
  let fs = @fs.MemFs::new()
  let streams = BufferedStreamHandler::new()
  let ctx = PosixContext::new(fs, streams)

  // Create and write
  let fd = ctx.open("/test.txt", OpenFlags::create_write())
  let _ = ctx.write(fd, b"Hello, World!")
  ctx.close(fd)

  // Read back
  let fd2 = ctx.open("/test.txt", OpenFlags::default())
  let data = ctx.read(fd2, 100)
  ctx.close(fd2)

  assert_eq(data.length(), 13)
}

test "PosixContext stdout/stderr" {
  let fs = @fs.MemFs::new()
  let streams = BufferedStreamHandler::new()
  let ctx = PosixContext::new(fs, streams)

  let _ = ctx.write(STDOUT_FD, b"stdout")
  let _ = ctx.write(STDERR_FD, b"stderr")

  assert_eq(streams.get_stdout(), b"stdout")
  assert_eq(streams.get_stderr(), b"stderr")
}

test "PosixContext resolve_path" {
  let fs = @fs.MemFs::new()
  let streams = BufferedStreamHandler::new()
  let ctx = PosixContext::new(fs, streams)

  assert_eq(ctx.resolve_path("/absolute"), "/absolute")
  assert_eq(ctx.resolve_path("relative"), "/relative")

  fs.mkdir("/home")
  ctx.chdir("/home")
  assert_eq(ctx.resolve_path("file.txt"), "/home/file.txt")
  assert_eq(ctx.resolve_path("../other"), "/other")
}
