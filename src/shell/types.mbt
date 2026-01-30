///| Shell execution context
pub struct ShellContext {
  fs : @fs.MemFs
  mut ctx : @posix.PosixContext
  mut streams : @posix.BufferedStreamHandler
  mut pipe_input : Bytes?
}

///| Create a new shell context
pub fn ShellContext::new() -> ShellContext {
  let fs = @fs.MemFs::new()
  let streams = @posix.BufferedStreamHandler::new()
  let ctx = @posix.PosixContext::new(fs, streams)
  { fs, ctx, streams, pipe_input: None }
}

///| Create shell context with existing filesystem
pub fn ShellContext::with_fs(fs : @fs.MemFs) -> ShellContext {
  let streams = @posix.BufferedStreamHandler::new()
  let ctx = @posix.PosixContext::new(fs, streams)
  { fs, ctx, streams, pipe_input: None }
}

///| Reset streams (call before each command)
pub fn ShellContext::reset_streams(self : ShellContext) -> Unit {
  self.streams = @posix.BufferedStreamHandler::new()
  let new_ctx = @posix.PosixContext::new(self.fs, self.streams)
  // Preserve cwd and env
  let cwd = self.ctx.getcwd()
  try { new_ctx.chdir(cwd) } catch { _ => () }
  for kv in self.ctx.get_all_env() {
    new_ctx.setenv(kv.0, kv.1)
  }
  self.ctx = new_ctx
}

///| Get stdout output
pub fn ShellContext::get_stdout(self : ShellContext) -> Bytes {
  self.streams.get_stdout()
}

///| Get stderr output
pub fn ShellContext::get_stderr(self : ShellContext) -> Bytes {
  self.streams.get_stderr()
}

///| Parsed command structure
pub struct ParsedCommand {
  command : String
  args : Array[String]
  redirect_out : String?
  pipe_to : String?
}

///| Get the filesystem
pub fn ShellContext::get_fs(self : ShellContext) -> @fs.MemFs {
  self.fs
}

///| Get the POSIX context
pub fn ShellContext::get_ctx(self : ShellContext) -> @posix.PosixContext {
  self.ctx
}
