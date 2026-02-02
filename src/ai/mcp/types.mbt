///| MCP (Model Context Protocol) types
///| Based on JSON-RPC 2.0

/// JSON-RPC request
pub(all) struct JsonRpcRequest {
  jsonrpc : String  // "2.0"
  id : Int
  rpc_method : String
  params : Json?
}

/// JSON-RPC response
pub(all) struct JsonRpcResponse {
  jsonrpc : String  // "2.0"
  id : Int
  result : Json?
  error : JsonRpcError?
}

/// JSON-RPC error
pub(all) struct JsonRpcError {
  code : Int
  message : String
  data : Json?
}

/// MCP Tool definition
pub(all) struct McpTool {
  name : String
  description : String
  input_schema : Json  // JSON Schema
}

/// MCP Resource definition
pub(all) struct McpResource {
  uri : String
  name : String
  description : String?
  mime_type : String?
}

/// MCP Prompt definition
pub(all) struct McpPrompt {
  name : String
  description : String?
  arguments : Array[McpPromptArgument]
}

/// MCP Prompt argument
pub(all) struct McpPromptArgument {
  name : String
  description : String?
  required : Bool
}

/// MCP Server capabilities
pub(all) struct McpServerCapabilities {
  tools : Bool
  resources : Bool
  prompts : Bool
}

/// MCP Initialize request params
pub(all) struct McpInitializeParams {
  protocol_version : String
  client_info : McpClientInfo
  capabilities : McpClientCapabilities
}

/// MCP Client info
pub(all) struct McpClientInfo {
  name : String
  version : String
}

/// MCP Client capabilities
pub(all) struct McpClientCapabilities {
  roots : Bool
  sampling : Bool
}

/// MCP Initialize result
pub(all) struct McpInitializeResult {
  protocol_version : String
  server_info : McpServerInfo
  capabilities : McpServerCapabilities
}

/// MCP Server info
pub(all) struct McpServerInfo {
  name : String
  version : String
}

/// MCP Tool call request params
pub(all) struct McpCallToolParams {
  name : String
  arguments : Json?
}

/// MCP Tool call result
pub(all) struct McpCallToolResult {
  content : Array[McpContent]
  is_error : Bool
}

/// MCP Content (text or image)
pub(all) enum McpContent {
  Text(String)
  Image(mime_type~ : String, data~ : String)  // base64 encoded
  Resource(uri~ : String, mime_type~ : String?, text~ : String?)
}

/// MCP List tools result
pub(all) struct McpListToolsResult {
  tools : Array[McpTool]
}

/// MCP List resources result
pub(all) struct McpListResourcesResult {
  resources : Array[McpResource]
}

/// MCP Read resource result
pub(all) struct McpReadResourceResult {
  contents : Array[McpResourceContent]
}

/// MCP Resource content
pub(all) struct McpResourceContent {
  uri : String
  mime_type : String?
  text : String?
  blob : String?  // base64 encoded
}

/// Create a JSON-RPC request
pub fn make_request(id : Int, rpc_method : String, params : Json?) -> JsonRpcRequest {
  { jsonrpc: "2.0", id, rpc_method, params }
}

/// Create a JSON-RPC success response
pub fn make_response(id : Int, result : Json) -> JsonRpcResponse {
  { jsonrpc: "2.0", id, result: Some(result), error: None }
}

/// Create a JSON-RPC error response
pub fn make_error_response(id : Int, code : Int, message : String) -> JsonRpcResponse {
  {
    jsonrpc: "2.0",
    id,
    result: None,
    error: Some({ code, message, data: None }),
  }
}
