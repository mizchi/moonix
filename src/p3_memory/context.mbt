///|
pub struct P3MemoryConfig {
  stdin : Bytes
  env : Map[String, String]
  args : Array[String]
  cwd : String
  prng_seed : UInt64
  wall_seconds : UInt64
  wall_nanoseconds : UInt
  preopens : Array[String]
}

///|
pub fn P3MemoryConfig::default() -> P3MemoryConfig {
  {
    stdin: b"",
    env: {},
    args: [],
    cwd: "/",
    prng_seed: 42UL,
    wall_seconds: 1700000000UL,
    wall_nanoseconds: 0,
    preopens: ["/"],
  }
}

///|
pub struct P3MemoryContext {
  kernel : Kernel
  cli : CliAdapter
  fs : FsAdapter
  clocks : ClocksAdapter
  random : RandomAdapter
  network : NetworkAdapter
  http : HttpAdapter
}

///|
pub fn P3MemoryContext::new(
  config : P3MemoryConfig,
  fs? : @fs.MemFs = @fs.MemFs::new(),
) -> P3MemoryContext {
  let kernel = Kernel::new(
    fs,
    stdin=config.stdin,
    env=config.env,
    args=config.args,
    cwd=config.cwd,
    prng_seed=config.prng_seed,
    wall_seconds=config.wall_seconds,
    wall_nanoseconds=config.wall_nanoseconds,
    preopens=config.preopens,
  )
  {
    kernel,
    cli: CliAdapter::new(kernel),
    fs: FsAdapter::new(kernel),
    clocks: ClocksAdapter::new(kernel),
    random: RandomAdapter::new(kernel),
    network: NetworkAdapter::new(),
    http: HttpAdapter::new(kernel),
  }
}

///|
pub fn P3MemoryContext::get_stdout(self : P3MemoryContext) -> Bytes {
  self.kernel.get_stdout_bytes()
}

///|
pub fn P3MemoryContext::get_stderr(self : P3MemoryContext) -> Bytes {
  self.kernel.get_stderr_bytes()
}

///|
pub fn P3MemoryContext::get_exit_code(self : P3MemoryContext) -> Int? {
  self.kernel.exit_code
}

///|
pub fn P3MemoryContext::get_fs(self : P3MemoryContext) -> @fs.MemFs {
  self.kernel.fs
}

///|
pub fn P3MemoryContext::register_http_handler(
  self : P3MemoryContext,
  handler : (String, String, Array[(String, Bytes)], Bytes) -> (
    Int,
    Array[(String, Bytes)],
    Bytes,
  ),
) -> Unit {
  self.kernel.http_mock_handler = Some(handler)
}
