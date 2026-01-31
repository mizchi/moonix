///| A2A Client - handler-based for WASI integration

/// HTTP transport handler type (same as MCP)
pub struct A2AHttpHandler {
  handler : (String, String, Bytes?) -> (Int, Bytes)
}

/// A2A Client error
pub suberror A2AClientError {
  HttpError(Int, String)
  ParseError(String)
  TaskNotFound(String)
  InvalidResponse(String)
  AgentUnavailable(String)
}

/// A2A Client
pub struct A2AClient {
  mut agent_card : AgentCard?
  endpoint : String
}

/// Convert Bytes to String
fn bytes_to_string(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

/// Escape string for JSON
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

/// Build JSON string
fn build_json_string(s : String) -> String {
  "\"" + escape_json_string(s) + "\""
}

/// Create new A2A client for a specific agent
pub fn A2AClient::new(endpoint : String) -> A2AClient {
  { agent_card: None, endpoint }
}

/// Fetch agent card (discovery)
pub fn A2AClient::discover(
  self : A2AClient,
  handler : A2AHttpHandler
) -> AgentCard raise A2AClientError {
  // Agent card is typically at /.well-known/agent.json
  let discovery_url = self.endpoint + "/.well-known/agent.json"
  let (status, body) = (handler.handler)("GET", discovery_url, None)

  if status != 200 {
    raise AgentUnavailable(self.endpoint)
  }

  let text = bytes_to_string(body)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }

  let card = parse_agent_card(json)
  self.agent_card = Some(card)
  card
}

/// Parse AgentCard from JSON
fn parse_agent_card(json : Json) -> AgentCard raise A2AClientError {
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => raise InvalidResponse("missing name")
      }
      let description = match obj.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let url = match obj.get("url") {
        Some(String(s)) => s
        _ => raise InvalidResponse("missing url")
      }
      let version = match obj.get("version") {
        Some(String(s)) => Some(s)
        _ => None
      }

      let capabilities = match obj.get("capabilities") {
        Some(Object(caps)) => {
          let streaming = caps.get("streaming") is Some(True)
          let push = caps.get("pushNotifications") is Some(True)
          let history = caps.get("stateTransitionHistory") is Some(True)
          { streaming, push_notifications: push, state_transition_history: history }
        }
        _ => AgentCapabilities::default()
      }

      let skills : Array[AgentSkill] = []
      match obj.get("skills") {
        Some(Array(skill_arr)) =>
          for skill in skill_arr {
            match skill {
              Object(s) => {
                let id = match s.get("id") {
                  Some(String(str)) => str
                  _ => continue
                }
                let skill_name = match s.get("name") {
                  Some(String(str)) => str
                  _ => ""
                }
                let skill_desc = match s.get("description") {
                  Some(String(str)) => str
                  _ => ""
                }
                let input_modes = parse_string_array(s.get("inputModes"))
                let output_modes = parse_string_array(s.get("outputModes"))
                let tags = parse_string_array(s.get("tags"))
                skills.push({
                  id,
                  name: skill_name,
                  description: skill_desc,
                  input_modes,
                  output_modes,
                  tags,
                })
              }
              _ => ()
            }
          }
        _ => ()
      }

      let default_input_modes = parse_string_array(obj.get("defaultInputModes"))
      let default_output_modes = parse_string_array(obj.get("defaultOutputModes"))

      let authentication : AgentAuth? = match obj.get("authentication") {
        Some(Object(auth)) => {
          let auth_type = match auth.get("type") {
            Some(String(s)) => s
            _ => "none"
          }
          let creds_url = match auth.get("credentialsUrl") {
            Some(String(s)) => Some(s)
            _ => None
          }
          Some({ auth_type, credentials_url: creds_url })
        }
        _ => None
      }

      {
        name,
        description,
        url,
        version,
        capabilities,
        skills,
        default_input_modes,
        default_output_modes,
        authentication,
      }
    }
    _ => raise InvalidResponse("expected object for agent card")
  }
}

/// Helper to parse string array from JSON
fn parse_string_array(json : Json?) -> Array[String] {
  let result : Array[String] = []
  match json {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  result
}

/// Send a task to the agent
pub fn A2AClient::send_task(
  self : A2AClient,
  request : TaskSendRequest,
  handler : A2AHttpHandler
) -> TaskSendResponse raise A2AClientError {
  let url = self.endpoint + "/tasks/send"
  let body = encode_task_send_request(request)
  let (status, response_body) = (handler.handler)("POST", url, Some(body))

  if status < 200 || status >= 300 {
    raise HttpError(status, bytes_to_string(response_body))
  }

  let text = bytes_to_string(response_body)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }

  parse_task_send_response(json)
}

/// Get task state
pub fn A2AClient::get_task(
  self : A2AClient,
  task_id : String,
  handler : A2AHttpHandler
) -> TaskState raise A2AClientError {
  let url = self.endpoint + "/tasks/" + task_id
  let (status, response_body) = (handler.handler)("GET", url, None)

  if status == 404 {
    raise TaskNotFound(task_id)
  }
  if status < 200 || status >= 300 {
    raise HttpError(status, bytes_to_string(response_body))
  }

  let text = bytes_to_string(response_body)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }

  parse_task_state(json)
}

/// Cancel a task
pub fn A2AClient::cancel_task(
  self : A2AClient,
  task_id : String,
  handler : A2AHttpHandler
) -> TaskCancelResponse raise A2AClientError {
  let url = self.endpoint + "/tasks/" + task_id + "/cancel"
  let (status, response_body) = (handler.handler)("POST", url, None)

  if status == 404 {
    raise TaskNotFound(task_id)
  }
  if status < 200 || status >= 300 {
    raise HttpError(status, bytes_to_string(response_body))
  }

  let text = bytes_to_string(response_body)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }

  match json {
    Object(obj) => {
      let tid = match obj.get("taskId") {
        Some(String(s)) => s
        _ => task_id
      }
      let cancelled = obj.get("cancelled") is Some(True)
      let message = match obj.get("message") {
        Some(String(s)) => Some(s)
        _ => None
      }
      { task_id: tid, cancelled, message }
    }
    _ => raise InvalidResponse("expected object for cancel response")
  }
}

/// Encode TaskSendRequest to JSON bytes
fn encode_task_send_request(req : TaskSendRequest) -> Bytes {
  let buf = StringBuilder::new()
  buf.write_string("{")

  let mut first = true
  match req.task_id {
    Some(id) => {
      buf.write_string("\"taskId\":")
      buf.write_string(build_json_string(id))
      first = false
    }
    None => ()
  }
  match req.skill_id {
    Some(id) => {
      if not(first) {
        buf.write_string(",")
      }
      buf.write_string("\"skillId\":")
      buf.write_string(build_json_string(id))
      first = false
    }
    None => ()
  }

  // Encode message
  if not(first) {
    buf.write_string(",")
  }
  buf.write_string("\"message\":{")
  buf.write_string("\"role\":")
  buf.write_string(build_json_string(req.message.role))
  buf.write_string(",\"parts\":[")

  for i, part in req.message.parts {
    if i > 0 {
      buf.write_string(",")
    }
    match part {
      Text(text) => {
        buf.write_string("{\"type\":\"text\",\"text\":")
        buf.write_string(build_json_string(text))
        buf.write_string("}")
      }
      File(mime_type~, data~, name~) => {
        buf.write_string("{\"type\":\"file\",\"mimeType\":")
        buf.write_string(build_json_string(mime_type))
        buf.write_string(",\"data\":")
        buf.write_string(build_json_string(data))
        match name {
          Some(n) => {
            buf.write_string(",\"name\":")
            buf.write_string(build_json_string(n))
          }
          None => ()
        }
        buf.write_string("}")
      }
      Data(mime_type~, data~) => {
        buf.write_string("{\"type\":\"data\",\"mimeType\":")
        buf.write_string(build_json_string(mime_type))
        buf.write_string(",\"data\":")
        buf.write_string(data.stringify())
        buf.write_string("}")
      }
    }
  }
  buf.write_string("]}")
  buf.write_string("}")

  buf.to_string().to_bytes()
}

/// Parse TaskSendResponse from JSON
fn parse_task_send_response(json : Json) -> TaskSendResponse raise A2AClientError {
  match json {
    Object(obj) => {
      let task_id = match obj.get("taskId") {
        Some(String(s)) => s
        _ => raise InvalidResponse("missing taskId")
      }
      let state = match obj.get("state") {
        Some(state_json) => parse_task_state(state_json)
        _ => TaskState::initial(task_id)
      }
      { task_id, state }
    }
    _ => raise InvalidResponse("expected object for task send response")
  }
}

/// Parse TaskState from JSON
fn parse_task_state(json : Json) -> TaskState raise A2AClientError {
  match json {
    Object(obj) => {
      let task_id = match obj.get("taskId") {
        Some(String(s)) => s
        _ => raise InvalidResponse("missing taskId in state")
      }
      let status_str = match obj.get("status") {
        Some(String(s)) => s
        _ => "submitted"
      }
      let status = match TaskStatus::from_string(status_str) {
        Some(s) => s
        None => Submitted
      }
      let message = match obj.get("message") {
        Some(String(s)) => Some(s)
        _ => None
      }

      let artifacts : Array[Artifact] = []
      match obj.get("artifacts") {
        Some(Array(arr)) =>
          for item in arr {
            match parse_artifact(item) {
              Some(a) => artifacts.push(a)
              None => ()
            }
          }
        _ => ()
      }

      let history : Array[TaskHistoryEntry] = []
      match obj.get("history") {
        Some(Array(arr)) =>
          for item in arr {
            match parse_history_entry(item) {
              Some(e) => history.push(e)
              None => ()
            }
          }
        _ => ()
      }

      { task_id, status, message, artifacts, history }
    }
    _ => raise InvalidResponse("expected object for task state")
  }
}

/// Parse Artifact from JSON
fn parse_artifact(json : Json) -> Artifact? {
  match json {
    Object(obj) => {
      let artifact_type = match obj.get("type") {
        Some(String(s)) => s
        _ => return None
      }
      let mime_type = match obj.get("mimeType") {
        Some(String(s)) => s
        _ => "application/octet-stream"
      }
      let name = match obj.get("name") {
        Some(String(s)) => Some(s)
        _ => None
      }

      let content = match obj.get("content") {
        Some(String(s)) => ArtifactContent::Text(s)
        Some(Object(c)) =>
          match c.get("uri") {
            Some(String(uri)) => ArtifactContent::Uri(uri)
            _ =>
              match c.get("data") {
                Some(String(data)) => ArtifactContent::Binary(data)
                _ => return None
              }
          }
        _ => return None
      }

      Some({ artifact_type, mime_type, name, content })
    }
    _ => None
  }
}

/// Parse TaskHistoryEntry from JSON
fn parse_history_entry(json : Json) -> TaskHistoryEntry? {
  match json {
    Object(obj) => {
      let timestamp = match obj.get("timestamp") {
        Some(Number(n)) => n.to_int64()
        _ => 0L
      }
      let status_str = match obj.get("status") {
        Some(String(s)) => s
        _ => return None
      }
      let status = match TaskStatus::from_string(status_str) {
        Some(s) => s
        None => return None
      }
      let message = match obj.get("message") {
        Some(String(s)) => Some(s)
        _ => None
      }
      Some({ timestamp, status, message })
    }
    _ => None
  }
}

/// Get cached agent card
pub fn A2AClient::get_agent_card(self : A2AClient) -> AgentCard? {
  self.agent_card
}

/// Check if agent has been discovered
pub fn A2AClient::is_discovered(self : A2AClient) -> Bool {
  self.agent_card is Some(_)
}
