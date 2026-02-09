///| A2A (Agent-to-Agent) Protocol types

///| Based on Google's A2A specification

///|
/// Agent Card - self-introduction for agent discovery
pub(all) struct AgentCard {
  name : String
  description : String
  url : String
  version : String?
  capabilities : AgentCapabilities
  skills : Array[AgentSkill]
  default_input_modes : Array[String]
  default_output_modes : Array[String]
  authentication : AgentAuth?
}

///|
/// Agent capabilities
pub(all) struct AgentCapabilities {
  streaming : Bool
  push_notifications : Bool
  state_transition_history : Bool
}

///|
/// Agent skill definition
pub(all) struct AgentSkill {
  id : String
  name : String
  description : String
  input_modes : Array[String]
  output_modes : Array[String]
  tags : Array[String]
}

///|
/// Agent authentication configuration
pub(all) struct AgentAuth {
  auth_type : String // "none", "api_key", "oauth2"
  credentials_url : String?
}

///|
/// Task status
pub(all) enum TaskStatus {
  Submitted
  Working
  InputRequired
  Completed
  Failed
  Cancelled
}

///|
/// Task state
pub(all) struct TaskState {
  task_id : String
  status : TaskStatus
  message : String?
  artifacts : Array[Artifact]
  history : Array[TaskHistoryEntry]
}

///|
/// Task history entry
pub(all) struct TaskHistoryEntry {
  timestamp : Int64
  status : TaskStatus
  message : String?
}

///|
/// Artifact (output from task)
pub(all) struct Artifact {
  artifact_type : String // "text", "file", "image", etc.
  mime_type : String
  name : String?
  content : ArtifactContent
}

///|
/// Artifact content
pub(all) enum ArtifactContent {
  Text(String)
  Binary(String) // base64 encoded
  Uri(String) // reference to external resource
}

///|
/// Task send request
pub(all) struct TaskSendRequest {
  task_id : String? // None for new task
  skill_id : String?
  message : Message
  push_notification_config : PushConfig?
}

///|
/// Message in task
pub(all) struct Message {
  role : String // "user", "agent"
  parts : Array[MessagePart]
}

///|
/// Message part
pub(all) enum MessagePart {
  Text(String)
  File(mime_type~ : String, data~ : String, name~ : String?)
  Data(mime_type~ : String, data~ : Json)
}

///|
/// Push notification configuration
pub(all) struct PushConfig {
  url : String
  authentication : AgentAuth?
}

///|
/// Task send response
pub(all) struct TaskSendResponse {
  task_id : String
  state : TaskState
}

///|
/// Task get request
pub(all) struct TaskGetRequest {
  task_id : String
  history_length : Int?
}

///|
/// Task cancel request
pub(all) struct TaskCancelRequest {
  task_id : String
}

///|
/// Task cancel response
pub(all) struct TaskCancelResponse {
  task_id : String
  cancelled : Bool
  message : String?
}

///|
/// Convert TaskStatus to string
pub fn TaskStatus::to_string(self : TaskStatus) -> String {
  match self {
    Submitted => "submitted"
    Working => "working"
    InputRequired => "input-required"
    Completed => "completed"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
/// Parse TaskStatus from string
pub fn TaskStatus::from_string(s : String) -> TaskStatus? {
  match s {
    "submitted" => Some(Submitted)
    "working" => Some(Working)
    "input-required" => Some(InputRequired)
    "completed" => Some(Completed)
    "failed" => Some(Failed)
    "cancelled" => Some(Cancelled)
    _ => None
  }
}

///|
/// Create minimal agent card
pub fn AgentCard::minimal(
  name : String,
  description : String,
  url : String,
) -> AgentCard {
  {
    name,
    description,
    url,
    version: None,
    capabilities: {
      streaming: false,
      push_notifications: false,
      state_transition_history: false,
    },
    skills: [],
    default_input_modes: ["text"],
    default_output_modes: ["text"],
    authentication: None,
  }
}

///|
/// Create default agent capabilities
pub fn AgentCapabilities::default() -> AgentCapabilities {
  {
    streaming: false,
    push_notifications: false,
    state_transition_history: true,
  }
}

///|
/// Create a text message
pub fn Message::text(role : String, text : String) -> Message {
  { role, parts: [Text(text)] }
}

///|
/// Create user text message
pub fn Message::user_text(text : String) -> Message {
  Message::text("user", text)
}

///|
/// Create agent text message
pub fn Message::agent_text(text : String) -> Message {
  Message::text("agent", text)
}

///|
/// Create initial task state
pub fn TaskState::initial(task_id : String) -> TaskState {
  { task_id, status: Submitted, message: None, artifacts: [], history: [] }
}
