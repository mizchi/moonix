///| LLM Client types for OpenRouter API

///|
/// Chat message role
pub enum Role {
  System
  User
  Assistant
  Tool
}

///|
/// Chat message
pub struct Message {
  role : Role
  content : String
  tool_call_id : String? // For tool responses
  tool_calls : Array[ToolCall]? // For assistant tool calls
}

///|
/// Tool call from assistant
pub struct ToolCall {
  id : String
  tool_type : String // "function"
  function : FunctionCall
}

///|
/// Function call details
pub struct FunctionCall {
  name : String
  arguments : String // JSON string
}

///|
/// Tool definition
pub struct Tool {
  tool_type : String // "function"
  function : FunctionDef
}

///|
/// Function definition
pub struct FunctionDef {
  name : String
  description : String
  parameters : Json // JSON Schema
}

///|
/// Chat completion request
pub struct ChatRequest {
  model : String
  messages : Array[Message]
  tools : Array[Tool]?
  tool_choice : String? // "auto", "none", or specific
  max_tokens : Int?
  temperature : Double?
}

///|
/// Chat completion response
pub struct ChatResponse {
  id : String
  model : String
  choices : Array[Choice]
  usage : Usage?
}

///|
/// Response choice
pub struct Choice {
  index : Int
  message : Message
  finish_reason : String // "stop", "tool_calls", "length"
}

///|
/// Token usage
pub struct Usage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
}

///|
/// LLM Client error
pub suberror LlmError {
  HttpError(Int, String)
  ParseError(String)
  ApiError(String)
  RateLimited
  InvalidResponse(String)
}

///|
/// Convert Role to string
pub fn Role::to_string(self : Role) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool => "tool"
  }
}

///|
/// Parse Role from string
pub fn Role::from_string(s : String) -> Role? {
  match s {
    "system" => Some(System)
    "user" => Some(User)
    "assistant" => Some(Assistant)
    "tool" => Some(Tool)
    _ => None
  }
}

///|
/// Create a system message
pub fn Message::system(content : String) -> Message {
  { role: System, content, tool_call_id: None, tool_calls: None }
}

///|
/// Create a user message
pub fn Message::user(content : String) -> Message {
  { role: User, content, tool_call_id: None, tool_calls: None }
}

///|
/// Create an assistant message
pub fn Message::assistant(content : String) -> Message {
  { role: Assistant, content, tool_call_id: None, tool_calls: None }
}

///|
/// Create a tool response message
pub fn Message::tool_response(
  tool_call_id : String,
  content : String,
) -> Message {
  { role: Tool, content, tool_call_id: Some(tool_call_id), tool_calls: None }
}

///|
/// Create a function tool definition
pub fn Tool::function(
  name : String,
  description : String,
  parameters : Json,
) -> Tool {
  { tool_type: "function", function: { name, description, parameters } }
}
