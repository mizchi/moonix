///| Effect kinds for external operations that cannot be rolled back

/// HTTP effect details
pub struct HttpEffectData {
  http_method : String
  url : String
  status : Int?
  request_body : Bytes?
  response_body : Bytes?
}

/// MCP effect details
pub struct McpEffectData {
  tool : String
  input : String?   // JSON string
  output : String?  // JSON string
}

/// A2A effect details
pub struct A2AEffectData {
  agent : String
  task_id : String
  message_type : String  // "request", "response", "status", "cancel"
  payload : String?      // JSON string
}

/// Socket effect details
pub struct SocketEffectData {
  host : String
  port : Int
  direction : String  // "connect", "send", "receive"
  data : Bytes?
}

/// Effect classification
pub enum EffectKind {
  // HTTP operations
  HttpRequest(HttpEffectData)

  // MCP tool calls
  McpToolCall(McpEffectData)

  // A2A communication
  A2AMessage(A2AEffectData)

  // Socket operations
  SocketOp(SocketEffectData)

  // Clock read (non-deterministic)
  WallClockRead(Int64)

  // Random generation (non-deterministic)
  RandomGenerate(Bytes)

  // Process spawn
  ProcessSpawn(String, Array[String], Int?) // cmd, args, exit_code
}

/// Single effect entry in the log
pub struct EffectEntry {
  /// Unique ID (content hash)
  id : String
  /// Monotonic timestamp
  timestamp : Int64
  /// Effect details
  kind : EffectKind
  /// Duration in nanoseconds
  duration_ns : Int64
  /// Parent git snapshot at execution time
  parent_snapshot : String?
  /// Sequence number in log
  seq : Int
}

/// Create a new effect entry
pub fn EffectEntry::new(
  kind : EffectKind,
  timestamp : Int64,
  duration_ns : Int64,
  parent_snapshot : String?,
  seq : Int
) -> EffectEntry {
  // Generate ID from content hash
  let id = generate_effect_id(kind, timestamp, seq)
  { id, timestamp, kind, duration_ns, parent_snapshot, seq }
}

/// Generate content-addressed ID for effect
fn generate_effect_id(kind : EffectKind, timestamp : Int64, seq : Int) -> String {
  // Simple hash combining kind description, timestamp, and seq
  let kind_str = effect_kind_to_string(kind)
  let combined = "\{kind_str}:\{timestamp}:\{seq}"
  // Use simple hash for now (could use SHA-1 later)
  simple_hash(combined)
}

/// Convert effect kind to string for hashing
fn effect_kind_to_string(kind : EffectKind) -> String {
  match kind {
    HttpRequest(data) => "http:\{data.http_method}:\{data.url}"
    McpToolCall(data) => "mcp:\{data.tool}"
    A2AMessage(data) => "a2a:\{data.agent}:\{data.task_id}"
    SocketOp(data) => "socket:\{data.host}:\{data.port}"
    WallClockRead(t) => "clock:\{t}"
    RandomGenerate(_) => "random"
    ProcessSpawn(cmd, _, _) => "process:\{cmd}"
  }
}

/// Simple string hash
fn simple_hash(s : String) -> String {
  let mut hash = 0
  for c in s {
    hash = (hash * 31 + c.to_int()) % 0x7FFFFFFF
  }
  hash.to_string()
}
