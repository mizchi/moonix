///| MCP Client - handler-based for WASI integration

/// HTTP transport handler type
pub struct HttpHandler {
  handler : (String, String, Bytes?) -> (Int, Bytes)
}

/// MCP Client configuration
pub(all) struct McpClientConfig {
  endpoint : String
  client_name : String
  client_version : String
}

/// MCP Client
pub struct McpClient {
  config : McpClientConfig
  mut request_id : Int
  mut initialized : Bool
  mut server_capabilities : McpServerCapabilities?
  mut server_info : McpServerInfo?
}

/// Client error
pub suberror McpClientError {
  NotInitialized
  HttpError(Int, String)
  ParseError(String)
  RpcError(Int, String)
  InvalidResponse(String)
}

/// Create new MCP client
pub fn McpClient::new(config : McpClientConfig) -> McpClient {
  {
    config,
    request_id: 0,
    initialized: false,
    server_capabilities: None,
    server_info: None,
  }
}

/// Get next request ID
fn McpClient::next_id(self : McpClient) -> Int {
  let id = self.request_id
  self.request_id = self.request_id + 1
  id
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

/// Build JSON number
fn build_json_number(n : Int) -> String {
  n.to_string()
}

/// Encode JSON-RPC request to bytes
fn encode_request(req : JsonRpcRequest) -> Bytes {
  let buf = StringBuilder::new()
  buf.write_string("{\"jsonrpc\":\"2.0\",\"id\":")
  buf.write_string(req.id.to_string())
  buf.write_string(",\"method\":")
  buf.write_string(build_json_string(req.rpc_method))
  match req.params {
    Some(p) => {
      buf.write_string(",\"params\":")
      buf.write_string(p.stringify())
    }
    None => ()
  }
  buf.write_string("}")
  buf.to_string().to_bytes()
}

/// Decode JSON-RPC response from bytes
fn decode_response(data : Bytes) -> JsonRpcResponse raise McpClientError {
  let text = bytes_to_string(data)
  let json = try {
    @json.parse(text)
  } catch {
    e => raise ParseError(e.to_string())
  }
  match json {
    Object(obj) => {
      let id = match obj.get("id") {
        Some(Number(n)) => n.to_int()
        _ => raise InvalidResponse("missing id")
      }
      let result = obj.get("result")
      let error : JsonRpcError? = match obj.get("error") {
        Some(Object(err_obj)) => {
          let code = match err_obj.get("code") {
            Some(Number(n)) => n.to_int()
            _ => 0
          }
          let message = match err_obj.get("message") {
            Some(String(s)) => s
            _ => "unknown error"
          }
          Some({ code, message, data: err_obj.get("data") })
        }
        _ => None
      }
      { jsonrpc: "2.0", id, result, error }
    }
    _ => raise InvalidResponse("expected object")
  }
}

/// Send request and get response
fn McpClient::send_request(
  self : McpClient,
  rpc_method : String,
  params : Json?,
  handler : HttpHandler
) -> Json raise McpClientError {
  let req = make_request(self.next_id(), rpc_method, params)
  let body = encode_request(req)

  let (status, response_body) = (handler.handler)("POST", self.config.endpoint, Some(body))

  if status < 200 || status >= 300 {
    raise HttpError(status, bytes_to_string(response_body))
  }

  let response = decode_response(response_body)

  match response.error {
    Some(err) => raise RpcError(err.code, err.message)
    None =>
      match response.result {
        Some(result) => result
        None =>
          try {
            @json.parse("null")
          } catch {
            _ => raise ParseError("null parse failed")
          }
      }
  }
}

/// Build initialize params JSON
fn build_initialize_params(client_name : String, client_version : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{")
  buf.write_string("\"protocolVersion\":\"2024-11-05\",")
  buf.write_string("\"clientInfo\":{")
  buf.write_string("\"name\":")
  buf.write_string(build_json_string(client_name))
  buf.write_string(",\"version\":")
  buf.write_string(build_json_string(client_version))
  buf.write_string("},")
  buf.write_string("\"capabilities\":{\"roots\":false,\"sampling\":false}")
  buf.write_string("}")
  buf.to_string()
}

/// Initialize connection to MCP server
pub fn McpClient::initialize(
  self : McpClient,
  handler : HttpHandler
) -> McpInitializeResult raise McpClientError {
  let params_str = build_initialize_params(
    self.config.client_name,
    self.config.client_version,
  )
  let params = try {
    @json.parse(params_str)
  } catch {
    e => raise ParseError(e.to_string())
  }

  let result = self.send_request("initialize", Some(params), handler)

  match result {
    Object(obj) => {
      let protocol_version = match obj.get("protocolVersion") {
        Some(String(s)) => s
        _ => "unknown"
      }

      let server_info : McpServerInfo = match obj.get("serverInfo") {
        Some(Object(si)) => {
          let name = match si.get("name") {
            Some(String(s)) => s
            _ => "unknown"
          }
          let version = match si.get("version") {
            Some(String(s)) => s
            _ => "unknown"
          }
          { name, version }
        }
        _ => { name: "unknown", version: "unknown" }
      }

      let capabilities = match obj.get("capabilities") {
        Some(Object(caps)) => {
          let tools = caps.get("tools") is Some(Object(_))
          let resources = caps.get("resources") is Some(Object(_))
          let prompts = caps.get("prompts") is Some(Object(_))
          { tools, resources, prompts }
        }
        _ => { tools: false, resources: false, prompts: false }
      }

      self.initialized = true
      self.server_info = Some(server_info)
      self.server_capabilities = Some(capabilities)

      { protocol_version, server_info, capabilities }
    }
    _ => raise InvalidResponse("expected object for initialize result")
  }
}

/// List available tools
pub fn McpClient::list_tools(
  self : McpClient,
  handler : HttpHandler
) -> Array[McpTool] raise McpClientError {
  if not(self.initialized) {
    raise NotInitialized
  }

  let result = self.send_request("tools/list", None, handler)

  match result {
    Object(obj) =>
      match obj.get("tools") {
        Some(Array(tools)) => {
          let parsed : Array[McpTool] = []
          for tool in tools {
            match tool {
              Object(t) => {
                let name = match t.get("name") {
                  Some(String(s)) => s
                  _ => continue
                }
                let description = match t.get("description") {
                  Some(String(s)) => s
                  _ => ""
                }
                let input_schema = match t.get("inputSchema") {
                  Some(schema) => schema
                  _ =>
                    try {
                      @json.parse("{}")
                    } catch {
                      _ => continue
                    }
                }
                parsed.push({ name, description, input_schema })
              }
              _ => ()
            }
          }
          parsed
        }
        _ => []
      }
    _ => []
  }
}

/// Build tool call params JSON
fn build_tool_call_params(name : String, arguments : Json?) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"name\":")
  buf.write_string(build_json_string(name))
  match arguments {
    Some(args) => {
      buf.write_string(",\"arguments\":")
      buf.write_string(args.stringify())
    }
    None => ()
  }
  buf.write_string("}")
  buf.to_string()
}

/// Call a tool
pub fn McpClient::call_tool(
  self : McpClient,
  name : String,
  arguments : Json?,
  handler : HttpHandler
) -> McpCallToolResult raise McpClientError {
  if not(self.initialized) {
    raise NotInitialized
  }

  let params_str = build_tool_call_params(name, arguments)
  let params = try {
    @json.parse(params_str)
  } catch {
    e => raise ParseError(e.to_string())
  }

  let result = self.send_request("tools/call", Some(params), handler)

  match result {
    Object(obj) => {
      let is_error = obj.get("isError") is Some(True)

      let content : Array[McpContent] = []
      match obj.get("content") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(c) =>
                match c.get("type") {
                  Some(String("text")) =>
                    match c.get("text") {
                      Some(String(text)) => content.push(McpContent::Text(text))
                      _ => ()
                    }
                  Some(String("image")) => {
                    let mime = match c.get("mimeType") {
                      Some(String(s)) => s
                      _ => "image/png"
                    }
                    let data = match c.get("data") {
                      Some(String(s)) => s
                      _ => ""
                    }
                    content.push(McpContent::Image(mime_type=mime, data~))
                  }
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }

      { content, is_error }
    }
    _ => { content: [], is_error: true }
  }
}

/// List resources
pub fn McpClient::list_resources(
  self : McpClient,
  handler : HttpHandler
) -> Array[McpResource] raise McpClientError {
  if not(self.initialized) {
    raise NotInitialized
  }

  let result = self.send_request("resources/list", None, handler)

  match result {
    Object(obj) =>
      match obj.get("resources") {
        Some(Array(resources)) => {
          let parsed : Array[McpResource] = []
          for res in resources {
            match res {
              Object(r) => {
                let uri = match r.get("uri") {
                  Some(String(s)) => s
                  _ => continue
                }
                let name = match r.get("name") {
                  Some(String(s)) => s
                  _ => ""
                }
                let description = match r.get("description") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                let mime_type = match r.get("mimeType") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                parsed.push({ uri, name, description, mime_type })
              }
              _ => ()
            }
          }
          parsed
        }
        _ => []
      }
    _ => []
  }
}

/// Read a resource
pub fn McpClient::read_resource(
  self : McpClient,
  uri : String,
  handler : HttpHandler
) -> McpReadResourceResult raise McpClientError {
  if not(self.initialized) {
    raise NotInitialized
  }

  let params_str = "{\"uri\":" + build_json_string(uri) + "}"
  let params = try {
    @json.parse(params_str)
  } catch {
    e => raise ParseError(e.to_string())
  }

  let result = self.send_request("resources/read", Some(params), handler)

  match result {
    Object(obj) => {
      let contents : Array[McpResourceContent] = []
      match obj.get("contents") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(c) => {
                let item_uri = match c.get("uri") {
                  Some(String(s)) => s
                  _ => continue
                }
                let mime_type = match c.get("mimeType") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                let text = match c.get("text") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                let blob = match c.get("blob") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                contents.push({ uri: item_uri, mime_type, text, blob })
              }
              _ => ()
            }
          }
        _ => ()
      }
      { contents }
    }
    _ => { contents: [] }
  }
}

/// Check if client is initialized
pub fn McpClient::is_initialized(self : McpClient) -> Bool {
  self.initialized
}

/// Get server info (after initialization)
pub fn McpClient::get_server_info(self : McpClient) -> McpServerInfo? {
  self.server_info
}

/// Get server capabilities (after initialization)
pub fn McpClient::get_server_capabilities(self : McpClient) -> McpServerCapabilities? {
  self.server_capabilities
}
