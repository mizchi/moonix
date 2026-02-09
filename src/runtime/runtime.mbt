///| Agent Runtime implementation

///|
/// The main runtime that integrates all components
pub struct AgentRuntime {
  /// Git-backed filesystem
  fs : @gitfs.GitBackedFs
  /// Effect log for irreversible operations
  effect_log : @effect.EffectLog
  /// Capability set for permission checking
  capabilities : @capability.CapabilitySet
  /// Current working directory
  mut cwd : String
  /// Environment variables
  env : Map[String, String]
  /// Timestamp provider
  mut timestamp_provider : () -> Int64
}

///|
/// Create a new agent runtime
pub fn AgentRuntime::new(config : RuntimeConfig) -> AgentRuntime {
  let fs = @gitfs.GitBackedFs::new(author=config.author)
  let effect_log = @effect.EffectLog::new()
  let env : Map[String, String] = {}
  env.set("HOME", "/home")
  env.set("PATH", "/bin:/usr/bin")
  env.set("PWD", "/")
  {
    fs,
    effect_log,
    capabilities: config.capabilities,
    cwd: "/",
    env,
    timestamp_provider: fn() { 0L },
  }
}

///|
/// Create with default sandbox configuration
pub fn AgentRuntime::sandbox() -> AgentRuntime {
  AgentRuntime::new(RuntimeConfig::default())
}

///|
/// Create with developer configuration
pub fn AgentRuntime::developer() -> AgentRuntime {
  AgentRuntime::new(RuntimeConfig::developer())
}

///|
/// Create with unrestricted configuration (for testing only)
pub fn AgentRuntime::unrestricted() -> AgentRuntime {
  AgentRuntime::new(RuntimeConfig::unrestricted())
}

///|
/// Set timestamp provider (for testing)
pub fn AgentRuntime::set_timestamp_provider(
  self : AgentRuntime,
  provider : () -> Int64,
) -> Unit {
  self.timestamp_provider = provider
  self.fs.set_timestamp_provider(provider)
  self.effect_log.set_timestamp_provider(provider)
}

///|
/// Get current timestamp
fn AgentRuntime::get_timestamp(self : AgentRuntime) -> Int64 {
  (self.timestamp_provider)()
}

// ============================================================================
// Filesystem Operations (with capability checks)
// ============================================================================

///|
/// Read a file (checks FsRead capability)
pub fn AgentRuntime::read_file(
  self : AgentRuntime,
  path : String,
) -> Bytes raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_read(abs_path)) {
    raise PermissionDenied("read: " + abs_path)
  }
  @fs.FileSystemBackend::read_file(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Read a file as string
pub fn AgentRuntime::read_string(
  self : AgentRuntime,
  path : String,
) -> String raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_read(abs_path)) {
    raise PermissionDenied("read: " + abs_path)
  }
  @fs.FileSystemBackend::read_string(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Write to a file (checks FsWrite capability)
pub fn AgentRuntime::write_file(
  self : AgentRuntime,
  path : String,
  data : Bytes,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_write(abs_path)) {
    raise PermissionDenied("write: " + abs_path)
  }
  @fs.FileSystemBackend::write_file(self.fs, abs_path, data) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Write string to a file
pub fn AgentRuntime::write_string(
  self : AgentRuntime,
  path : String,
  content : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_write(abs_path)) {
    raise PermissionDenied("write: " + abs_path)
  }
  @fs.FileSystemBackend::write_string(self.fs, abs_path, content) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Check if path exists
pub fn AgentRuntime::exists(self : AgentRuntime, path : String) -> Bool {
  let abs_path = self.resolve_path(path)
  // Existence check doesn't require capability
  @fs.FileSystemBackend::exists(self.fs, abs_path)
}

///|
/// Check if path is a file
pub fn AgentRuntime::is_file(self : AgentRuntime, path : String) -> Bool {
  let abs_path = self.resolve_path(path)
  @fs.FileSystemBackend::is_file(self.fs, abs_path)
}

///|
/// Check if path is a directory
pub fn AgentRuntime::is_dir(self : AgentRuntime, path : String) -> Bool {
  let abs_path = self.resolve_path(path)
  @fs.FileSystemBackend::is_dir(self.fs, abs_path)
}

///|
/// Create a directory
pub fn AgentRuntime::mkdir(
  self : AgentRuntime,
  path : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_write(abs_path)) {
    raise PermissionDenied("mkdir: " + abs_path)
  }
  @fs.FileSystemBackend::mkdir(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Create directory and parents
pub fn AgentRuntime::mkdir_p(
  self : AgentRuntime,
  path : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_write(abs_path)) {
    raise PermissionDenied("mkdir_p: " + abs_path)
  }
  @fs.FileSystemBackend::mkdir_p(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Remove a file
pub fn AgentRuntime::remove(
  self : AgentRuntime,
  path : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_delete(abs_path)) {
    raise PermissionDenied("remove: " + abs_path)
  }
  @fs.FileSystemBackend::remove(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// Remove directory and contents
pub fn AgentRuntime::rm_rf(
  self : AgentRuntime,
  path : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_delete(abs_path)) {
    raise PermissionDenied("rm_rf: " + abs_path)
  }
  @fs.FileSystemBackend::rm_rf(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

///|
/// List directory contents
pub fn AgentRuntime::readdir(
  self : AgentRuntime,
  path : String,
) -> Array[@fs.DirEntry] raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(self.capabilities.can_read(abs_path)) {
    raise PermissionDenied("readdir: " + abs_path)
  }
  @fs.FileSystemBackend::readdir(self.fs, abs_path) catch {
    e => raise IoError(e.to_string())
  }
}

// ============================================================================
// Path and Environment
// ============================================================================

///|
/// Resolve path to absolute
pub fn AgentRuntime::resolve_path(self : AgentRuntime, path : String) -> String {
  if path.has_prefix("/") {
    @fs.normalize_path(path)
  } else {
    @fs.normalize_path(self.cwd + "/" + path)
  }
}

///|
/// Get current working directory
pub fn AgentRuntime::getcwd(self : AgentRuntime) -> String {
  self.cwd
}

///|
/// Change working directory
pub fn AgentRuntime::chdir(
  self : AgentRuntime,
  path : String,
) -> Unit raise RuntimeError {
  let abs_path = self.resolve_path(path)
  if not(@fs.FileSystemBackend::is_dir(self.fs, abs_path)) {
    raise IoError("not a directory: " + abs_path)
  }
  self.cwd = abs_path
  self.env.set("PWD", abs_path)
}

///|
/// Get environment variable
pub fn AgentRuntime::getenv(self : AgentRuntime, name : String) -> String? {
  if not(self.capabilities.can_read_env(name)) {
    return None
  }
  self.env.get(name)
}

///|
/// Set environment variable
pub fn AgentRuntime::setenv(
  self : AgentRuntime,
  name : String,
  value : String,
) -> Unit {
  // setenv typically doesn't need capability check for own env
  self.env.set(name, value)
}

///|
/// Get all environment variables
pub fn AgentRuntime::get_all_env(
  self : AgentRuntime,
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for k, v in self.env {
    if self.capabilities.can_read_env(k) {
      result.push((k, v))
    }
  }
  result
}
