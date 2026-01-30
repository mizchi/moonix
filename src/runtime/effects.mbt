///| External effect interception and logging

// ============================================================================
// Clock Operations (Non-deterministic, logged)
// ============================================================================

/// Read wall clock time (logs effect)
pub fn AgentRuntime::wall_clock(self : AgentRuntime) -> Int64 raise RuntimeError {
  if not(self.capabilities.can_read_clock()) {
    raise PermissionDenied("clock_read")
  }

  let time = self.get_timestamp()

  // Log the effect
  let _ = self.effect_log.record_clock(time)

  time
}

// ============================================================================
// Random Operations (Non-deterministic, logged)
// ============================================================================

/// Generate random bytes (logs effect)
pub fn AgentRuntime::random_bytes(
  self : AgentRuntime,
  len : Int
) -> Bytes raise RuntimeError {
  if not(self.capabilities.can_read_random()) {
    raise PermissionDenied("random_read")
  }

  // Generate pseudo-random bytes (deterministic for testing)
  // In production, this would call WASI random
  let time = self.get_timestamp()
  let mut seed = time.to_int()
  let bytes = Bytes::makei(len, fn(i) {
    seed = (seed * 1103515245 + 12345) % 0x7FFFFFFF
    ((seed + i) % 256).to_byte()
  })

  // Log the effect
  let _ = self.effect_log.record_random(bytes)

  bytes
}

// ============================================================================
// HTTP Operations (Irreversible, logged)
// ============================================================================

/// HTTP request result
pub(all) struct HttpResponse {
  status : Int
  body : Bytes
}

/// Perform HTTP request (logs effect)
/// Note: This is a stub that would be implemented by WASI host
pub fn AgentRuntime::http_request(
  self : AgentRuntime,
  http_method : String,
  url : String,
  body : Bytes?,
  handler : (String, String, Bytes?) -> HttpResponse
) -> HttpResponse raise RuntimeError {
  // Extract host from URL for capability check
  let host = extract_host(url)
  if not(self.capabilities.can_connect(host, 443)) {
    raise PermissionDenied("http_connect: " + host)
  }

  let start_time = self.get_timestamp()

  // Perform the request (via handler)
  let response = handler(http_method, url, body)

  let end_time = self.get_timestamp()
  let duration_ns = (end_time - start_time) * 1_000_000L

  // Log the effect
  let _ = self.effect_log.record_http(
    http_method,
    url,
    Some(response.status),
    body,
    Some(response.body),
    duration_ns~,
  )

  response
}

/// Extract host from URL
fn extract_host(url : String) -> String {
  // Simple URL parsing - extract host
  // https://api.example.com/path -> api.example.com
  let url_str = url
  let without_proto = if url_str.has_prefix("https://") {
    let chars = url_str.to_array()
    let mut result = ""
    for i = 8; i < chars.length(); i = i + 1 {
      result = result + chars[i].to_string()
    }
    result
  } else if url_str.has_prefix("http://") {
    let chars = url_str.to_array()
    let mut result = ""
    for i = 7; i < chars.length(); i = i + 1 {
      result = result + chars[i].to_string()
    }
    result
  } else {
    url_str
  }

  // Find first / and take everything before it
  let chars = without_proto.to_array()
  let mut host = ""
  for c in chars {
    if c == '/' || c == ':' {
      break
    }
    host = host + c.to_string()
  }
  host
}

// ============================================================================
// MCP Operations (Irreversible, logged)
// ============================================================================

/// MCP tool call result
pub(all) struct McpResult {
  success : Bool
  output : String?
  error : String?
}

/// Call an MCP tool (logs effect)
pub fn AgentRuntime::mcp_call(
  self : AgentRuntime,
  tool : String,
  input : String?,
  handler : (String, String?) -> McpResult
) -> McpResult raise RuntimeError {
  if not(self.capabilities.can_call_mcp(tool)) {
    raise PermissionDenied("mcp_call: " + tool)
  }

  let start_time = self.get_timestamp()

  // Perform the call (via handler)
  let result = handler(tool, input)

  let end_time = self.get_timestamp()
  let duration_ns = (end_time - start_time) * 1_000_000L

  // Log the effect
  let _ = self.effect_log.record_mcp(tool, input, result.output, duration_ns~)

  result
}

// ============================================================================
// A2A Operations (Irreversible, logged)
// ============================================================================

/// A2A task result
pub(all) struct A2ATaskResult {
  task_id : String
  status : String
  result : String?
}

/// Delegate task to another agent (logs effect)
pub fn AgentRuntime::a2a_delegate(
  self : AgentRuntime,
  agent : String,
  task_id : String,
  prompt : String,
  handler : (String, String, String) -> A2ATaskResult
) -> A2ATaskResult raise RuntimeError {
  if not(self.capabilities.can_delegate_a2a(agent)) {
    raise PermissionDenied("a2a_delegate: " + agent)
  }

  let start_time = self.get_timestamp()

  // Perform delegation (via handler)
  let result = handler(agent, task_id, prompt)

  let end_time = self.get_timestamp()
  let duration_ns = (end_time - start_time) * 1_000_000L

  // Log the effect
  let _ = self.effect_log.record_a2a(
    agent,
    task_id,
    "request",
    Some(prompt),
    duration_ns~,
  )

  result
}

// ============================================================================
// Process Operations (Irreversible, logged)
// ============================================================================

/// Process execution result
pub(all) struct ProcessResult {
  exit_code : Int
  stdout : Bytes
  stderr : Bytes
}

/// Spawn a process (logs effect)
pub fn AgentRuntime::spawn_process(
  self : AgentRuntime,
  cmd : String,
  args : Array[String],
  handler : (String, Array[String]) -> ProcessResult
) -> ProcessResult raise RuntimeError {
  if not(self.capabilities.can_spawn(cmd)) {
    raise PermissionDenied("spawn: " + cmd)
  }

  let start_time = self.get_timestamp()

  // Perform spawn (via handler)
  let result = handler(cmd, args)

  let end_time = self.get_timestamp()
  let duration_ns = (end_time - start_time) * 1_000_000L

  // Log the effect
  let _ = self.effect_log.record_process(
    cmd,
    args,
    Some(result.exit_code),
    duration_ns~,
  )

  result
}

// ============================================================================
// Effect Log Access
// ============================================================================

/// Get all recorded effects
pub fn AgentRuntime::get_effects(self : AgentRuntime) -> Array[@effect.EffectEntry] {
  self.effect_log.get_entries()
}

/// Get effects after a specific point
pub fn AgentRuntime::get_effects_after(
  self : AgentRuntime,
  seq : Int
) -> Array[@effect.EffectEntry] {
  self.effect_log.entries_after(seq)
}

/// Get HTTP effects only
pub fn AgentRuntime::get_http_effects(self : AgentRuntime) -> Array[@effect.EffectEntry] {
  self.effect_log.http_effects()
}

/// Get MCP effects only
pub fn AgentRuntime::get_mcp_effects(self : AgentRuntime) -> Array[@effect.EffectEntry] {
  self.effect_log.mcp_effects()
}

/// Get effect log head position
pub fn AgentRuntime::get_effect_log_head(self : AgentRuntime) -> Int {
  self.effect_log.head()
}
