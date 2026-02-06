///| WASM runner callback type
/// (wasm_bytes, stdin, args, env, cwd) -> Result[(exit_code, stdout, stderr), error_msg]
pub(all) struct WasmRunnerFn(
  (Bytes, Bytes, Array[String], Array[(String, String)], String) -> Result[(Int, Bytes, Bytes), String]
)

///| Shell execution context
pub struct ShellContext {
  fs : &@fs.FileSystemBackend
  mut ctx : @posix.PosixContext
  mut streams : @posix.BufferedStreamHandler
  mut pipe_input : Bytes?
  mut wasm_runner : WasmRunnerFn?
  mut last_exit_code : Int
  git_store : @bit.TestFs
  mut snapshot_head : @bit.ObjectId?
  mut snapshot_clock : Int64
  snapshot_store : Map[String, Map[String, Bytes]]
  xsh_runtime : @xsh.Runtime
}

///| Create a new shell context
pub fn ShellContext::new() -> ShellContext {
  let fs = @fs.MemFs::new()
  let streams = @posix.BufferedStreamHandler::new()
  let ctx = @posix.PosixContext::new(fs, streams)
  {
    fs,
    ctx,
    streams,
    pipe_input: None,
    wasm_runner: None,
    last_exit_code: 0,
    git_store: @bit.TestFs::new(),
    snapshot_head: None,
    snapshot_clock: 0L,
    snapshot_store: {},
    xsh_runtime: @xsh.Runtime::new(@xsh_capability.CapabilitySet::new()),
  }
}

///| Create shell context with existing filesystem
pub fn ShellContext::with_fs(fs : &@fs.FileSystemBackend) -> ShellContext {
  let streams = @posix.BufferedStreamHandler::new()
  let ctx = @posix.PosixContext::new(fs, streams)
  {
    fs,
    ctx,
    streams,
    pipe_input: None,
    wasm_runner: None,
    last_exit_code: 0,
    git_store: @bit.TestFs::new(),
    snapshot_head: None,
    snapshot_clock: 0L,
    snapshot_store: {},
    xsh_runtime: @xsh.Runtime::new(@xsh_capability.CapabilitySet::new()),
  }
}

///| Set WASM runner callback
pub fn ShellContext::set_wasm_runner(self : ShellContext, runner : WasmRunnerFn) -> Unit {
  self.wasm_runner = Some(runner)
}

///| Set pipe input (for testing and programmatic use)
pub fn ShellContext::set_pipe_input(self : ShellContext, data : Bytes) -> Unit {
  self.pipe_input = Some(data)
}

///| Clear pipe input
pub fn ShellContext::clear_pipe_input(self : ShellContext) -> Unit {
  self.pipe_input = None
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
pub fn ShellContext::get_fs(self : ShellContext) -> &@fs.FileSystemBackend {
  self.fs
}

///| Get the POSIX context
pub fn ShellContext::get_ctx(self : ShellContext) -> @posix.PosixContext {
  self.ctx
}

///| Get last exit code ($?)
pub fn ShellContext::get_last_exit_code(self : ShellContext) -> Int {
  self.last_exit_code
}

///| Get current snapshot hash (full hex)
pub fn ShellContext::current_hash(self : ShellContext) -> String {
  match self.snapshot_head {
    Some(id) => id.to_hex()
    None => @bit.ObjectId::zero().to_hex()
  }
}

///| Render shell prompt with current snapshot hash
pub fn ShellContext::prompt(self : ShellContext) -> String {
  let hex = self.current_hash()
  let short = if hex.length() > 7 {
    String::unsafe_substring(hex, start=0, end=7)
  } else {
    hex
  }
  "[" + short + "]$ "
}

fn ShellContext::next_snapshot_timestamp(self : ShellContext) -> Int64 {
  let t = self.snapshot_clock
  self.snapshot_clock += 1L
  t
}
