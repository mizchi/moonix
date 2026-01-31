///| OpenRouter LLM Client - handler-based for WASI integration

/// HTTP handler type
pub struct LlmHttpHandler {
  handler : (String, String, Bytes?) -> (Int, Bytes)
}

/// OpenRouter client configuration
pub struct OpenRouterConfig {
  api_key : String
  base_url : String
  default_model : String
}

/// OpenRouter client
pub struct OpenRouterClient {
  config : OpenRouterConfig
}

/// Create default config
pub fn OpenRouterConfig::default(api_key : String) -> OpenRouterConfig {
  {
    api_key,
    base_url: "https://openrouter.ai/api/v1",
    default_model: "anthropic/claude-3.5-sonnet",
  }
}

/// Create new client
pub fn OpenRouterClient::new(config : OpenRouterConfig) -> OpenRouterClient {
  { config }
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

/// Build JSON string value
fn json_string(s : String) -> String {
  "\"" + escape_json_string(s) + "\""
}

/// Encode chat request to JSON bytes
fn encode_request(req : ChatRequest, api_key : String) -> (Bytes, String) {
  let buf = StringBuilder::new()
  buf.write_string("{")
  buf.write_string("\"model\":")
  buf.write_string(json_string(req.model))
  buf.write_string(",\"messages\":[")

  for i, msg in req.messages {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{\"role\":")
    buf.write_string(json_string(msg.role.to_string()))
    buf.write_string(",\"content\":")
    buf.write_string(json_string(msg.content))
    match msg.tool_call_id {
      Some(id) => {
        buf.write_string(",\"tool_call_id\":")
        buf.write_string(json_string(id))
      }
      None => ()
    }
    match msg.tool_calls {
      Some(calls) if calls.length() > 0 => {
        buf.write_string(",\"tool_calls\":[")
        for j, call in calls {
          if j > 0 {
            buf.write_string(",")
          }
          buf.write_string("{\"id\":")
          buf.write_string(json_string(call.id))
          buf.write_string(",\"type\":")
          buf.write_string(json_string(call.tool_type))
          buf.write_string(",\"function\":{\"name\":")
          buf.write_string(json_string(call.function.name))
          buf.write_string(",\"arguments\":")
          buf.write_string(json_string(call.function.arguments))
          buf.write_string("}}")
        }
        buf.write_string("]")
      }
      _ => ()
    }
    buf.write_string("}")
  }
  buf.write_string("]")

  // Tools
  match req.tools {
    Some(tools) if tools.length() > 0 => {
      buf.write_string(",\"tools\":[")
      for i, tool in tools {
        if i > 0 {
          buf.write_string(",")
        }
        buf.write_string("{\"type\":")
        buf.write_string(json_string(tool.tool_type))
        buf.write_string(",\"function\":{\"name\":")
        buf.write_string(json_string(tool.function.name))
        buf.write_string(",\"description\":")
        buf.write_string(json_string(tool.function.description))
        buf.write_string(",\"parameters\":")
        buf.write_string(tool.function.parameters.stringify())
        buf.write_string("}}")
      }
      buf.write_string("]")
    }
    _ => ()
  }

  // Optional parameters
  match req.max_tokens {
    Some(n) => {
      buf.write_string(",\"max_tokens\":")
      buf.write_string(n.to_string())
    }
    None => ()
  }
  match req.temperature {
    Some(t) => {
      buf.write_string(",\"temperature\":")
      buf.write_string(t.to_string())
    }
    None => ()
  }
  match req.tool_choice {
    Some(choice) => {
      buf.write_string(",\"tool_choice\":")
      buf.write_string(json_string(choice))
    }
    None => ()
  }

  buf.write_string("}")

  let auth = "Bearer " + api_key
  (buf.to_string().to_bytes(), auth)
}

/// Decode chat response from JSON
fn decode_response(data : Bytes) -> ChatResponse raise LlmError {
  let text = bytes_to_string(data)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }

  match json {
    Object(obj) => {
      // Check for error
      match obj.get("error") {
        Some(Object(err)) => {
          let msg = match err.get("message") {
            Some(String(s)) => s
            _ => "Unknown error"
          }
          raise ApiError(msg)
        }
        _ => ()
      }

      let id = match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      let model = match obj.get("model") {
        Some(String(s)) => s
        _ => ""
      }

      let choices : Array[Choice] = []
      match obj.get("choices") {
        Some(Array(arr)) => {
          for item in arr {
            match item {
              Object(c) => {
                let index = match c.get("index") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
                let finish_reason = match c.get("finish_reason") {
                  Some(String(s)) => s
                  _ => "stop"
                }
                let message = match c.get("message") {
                  Some(Object(m)) => parse_message(m)
                  _ => Message::assistant("")
                }
                choices.push({ index, message, finish_reason })
              }
              _ => ()
            }
          }
        }
        _ => ()
      }

      let usage : Usage? = match obj.get("usage") {
        Some(Object(u)) => {
          let prompt = match u.get("prompt_tokens") {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          let completion = match u.get("completion_tokens") {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          Some({
            prompt_tokens: prompt,
            completion_tokens: completion,
            total_tokens: prompt + completion,
          })
        }
        _ => None
      }

      { id, model, choices, usage }
    }
    _ => raise InvalidResponse("expected object")
  }
}

/// Parse message from JSON object
fn parse_message(obj : Map[String, Json]) -> Message {
  let role = match obj.get("role") {
    Some(String(s)) => Role::from_string(s).or(Assistant)
    _ => Assistant
  }
  let content = match obj.get("content") {
    Some(String(s)) => s
    Some(Null) => ""
    _ => ""
  }
  let tool_call_id = match obj.get("tool_call_id") {
    Some(String(s)) => Some(s)
    _ => None
  }

  let tool_calls : Array[ToolCall]? = match obj.get("tool_calls") {
    Some(Array(arr)) => {
      let calls : Array[ToolCall] = []
      for item in arr {
        match item {
          Object(tc) => {
            let id = match tc.get("id") {
              Some(String(s)) => s
              _ => ""
            }
            let tool_type = match tc.get("type") {
              Some(String(s)) => s
              _ => "function"
            }
            let function = match tc.get("function") {
              Some(Object(f)) => {
                let name = match f.get("name") {
                  Some(String(s)) => s
                  _ => ""
                }
                let arguments = match f.get("arguments") {
                  Some(String(s)) => s
                  _ => "{}"
                }
                { name, arguments }
              }
              _ => { name: "", arguments: "{}" }
            }
            calls.push({ id, tool_type, function })
          }
          _ => ()
        }
      }
      if calls.length() > 0 { Some(calls) } else { None }
    }
    _ => None
  }

  { role, content, tool_call_id, tool_calls }
}

/// Send chat completion request
pub fn OpenRouterClient::chat(
  self : OpenRouterClient,
  messages : Array[Message],
  handler : LlmHttpHandler,
  tools~ : Array[Tool]? = None,
  model~ : String? = None,
  max_tokens~ : Int? = None,
  temperature~ : Double? = None
) -> ChatResponse raise LlmError {
  let req : ChatRequest = {
    model: model.or(self.config.default_model),
    messages,
    tools,
    tool_choice: if tools is Some(_) { Some("auto") } else { None },
    max_tokens,
    temperature,
  }

  let url = self.config.base_url + "/chat/completions"
  let (body, _auth) = encode_request(req, self.config.api_key)

  // Note: The handler should add Authorization header
  let (status, response_body) = (handler.handler)("POST", url, Some(body))

  if status == 429 {
    raise RateLimited
  }
  if status < 200 || status >= 300 {
    raise HttpError(status, bytes_to_string(response_body))
  }

  decode_response(response_body)
}

/// Simple chat without tools
pub fn OpenRouterClient::simple_chat(
  self : OpenRouterClient,
  prompt : String,
  handler : LlmHttpHandler,
  system~ : String? = None,
  model~ : String? = None
) -> String raise LlmError {
  let messages : Array[Message] = []
  match system {
    Some(s) => messages.push(Message::system(s))
    None => ()
  }
  messages.push(Message::user(prompt))

  let response = self.chat(messages, handler, model~)

  if response.choices.length() == 0 {
    raise InvalidResponse("no choices")
  }
  response.choices[0].message.content
}
