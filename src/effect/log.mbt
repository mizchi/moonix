///| Append-only effect log for irreversible operations

/// Effect log - append-only log of irreversible effects
pub struct EffectLog {
  /// All recorded effects
  mut entries : Array[EffectEntry]
  /// Current sequence number
  mut seq : Int
  /// Timestamp provider (for testing)
  mut timestamp_provider : () -> Int64
  /// Current parent snapshot (git commit)
  mut current_snapshot : String?
}

/// Create a new empty effect log
pub fn EffectLog::new() -> EffectLog {
  {
    entries: [],
    seq: 0,
    timestamp_provider: fn() { 0L },
    current_snapshot: None,
  }
}

/// Set timestamp provider (for testing)
pub fn EffectLog::set_timestamp_provider(
  self : EffectLog,
  provider : () -> Int64
) -> Unit {
  self.timestamp_provider = provider
}

/// Update current snapshot reference
pub fn EffectLog::set_current_snapshot(
  self : EffectLog,
  snapshot : String?
) -> Unit {
  self.current_snapshot = snapshot
}

/// Get current timestamp
fn EffectLog::get_timestamp(self : EffectLog) -> Int64 {
  (self.timestamp_provider)()
}

/// Record an effect
pub fn EffectLog::record(
  self : EffectLog,
  kind : EffectKind,
  duration_ns~ : Int64 = 0L
) -> EffectEntry {
  let timestamp = self.get_timestamp()
  let entry = EffectEntry::new(
    kind,
    timestamp,
    duration_ns,
    self.current_snapshot,
    self.seq,
  )
  self.entries.push(entry)
  self.seq = self.seq + 1
  entry
}

/// Record HTTP request
pub fn EffectLog::record_http(
  self : EffectLog,
  http_method : String,
  url : String,
  status : Int?,
  request_body : Bytes?,
  response_body : Bytes?,
  duration_ns~ : Int64 = 0L
) -> EffectEntry {
  let data : HttpEffectData = { http_method, url, status, request_body, response_body }
  self.record(HttpRequest(data), duration_ns~)
}

/// Record MCP tool call
pub fn EffectLog::record_mcp(
  self : EffectLog,
  tool : String,
  input : String?,
  output : String?,
  duration_ns~ : Int64 = 0L
) -> EffectEntry {
  let data : McpEffectData = { tool, input, output }
  self.record(McpToolCall(data), duration_ns~)
}

/// Record A2A message
pub fn EffectLog::record_a2a(
  self : EffectLog,
  agent : String,
  task_id : String,
  message_type : String,
  payload : String?,
  duration_ns~ : Int64 = 0L
) -> EffectEntry {
  let data : A2AEffectData = { agent, task_id, message_type, payload }
  self.record(A2AMessage(data), duration_ns~)
}

/// Record wall clock read
pub fn EffectLog::record_clock(
  self : EffectLog,
  time : Int64
) -> EffectEntry {
  self.record(WallClockRead(time))
}

/// Record random generation
pub fn EffectLog::record_random(
  self : EffectLog,
  bytes : Bytes
) -> EffectEntry {
  self.record(RandomGenerate(bytes))
}

/// Record process spawn
pub fn EffectLog::record_process(
  self : EffectLog,
  cmd : String,
  args : Array[String],
  exit_code : Int?,
  duration_ns~ : Int64 = 0L
) -> EffectEntry {
  self.record(ProcessSpawn(cmd, args, exit_code), duration_ns~)
}

/// Get all entries
pub fn EffectLog::get_entries(self : EffectLog) -> Array[EffectEntry] {
  self.entries
}

/// Get entry count
pub fn EffectLog::length(self : EffectLog) -> Int {
  self.entries.length()
}

/// Get entries after a specific sequence number
pub fn EffectLog::entries_after(self : EffectLog, seq : Int) -> Array[EffectEntry] {
  let result : Array[EffectEntry] = []
  for entry in self.entries {
    if entry.seq > seq {
      result.push(entry)
    }
  }
  result
}

/// Get entries after a specific snapshot
pub fn EffectLog::entries_after_snapshot(
  self : EffectLog,
  snapshot : String
) -> Array[EffectEntry] {
  let result : Array[EffectEntry] = []
  let mut found = false
  for entry in self.entries {
    if found {
      result.push(entry)
    } else {
      match entry.parent_snapshot {
        Some(s) if s == snapshot => found = true
        _ => ()
      }
    }
  }
  result
}

/// Filter entries by kind
pub fn EffectLog::filter_by_kind(
  self : EffectLog,
  filter : (EffectKind) -> Bool
) -> Array[EffectEntry] {
  let result : Array[EffectEntry] = []
  for entry in self.entries {
    if filter(entry.kind) {
      result.push(entry)
    }
  }
  result
}

/// Get HTTP effects only
pub fn EffectLog::http_effects(self : EffectLog) -> Array[EffectEntry] {
  self.filter_by_kind(fn(kind) {
    match kind {
      HttpRequest(_) => true
      _ => false
    }
  })
}

/// Get MCP effects only
pub fn EffectLog::mcp_effects(self : EffectLog) -> Array[EffectEntry] {
  self.filter_by_kind(fn(kind) {
    match kind {
      McpToolCall(_) => true
      _ => false
    }
  })
}

/// Clear all entries (for testing)
pub fn EffectLog::clear(self : EffectLog) -> Unit {
  self.entries = []
  self.seq = 0
}

/// Get the current head position (sequence number)
pub fn EffectLog::head(self : EffectLog) -> Int {
  self.seq
}
