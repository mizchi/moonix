///| Agent types for goal-oriented autonomous execution

/// Goal verification result
pub enum GoalStatus {
  Achieved           // Goal is satisfied
  InProgress         // Still working towards goal
  Failed(String)     // Cannot achieve goal
  Timeout            // Exceeded step limit
}

/// Goal definition - verifiable condition
pub struct Goal {
  name : String
  description : String
  /// Predicate to check if goal is achieved
  check : (@runtime.AgentRuntime) -> Bool
}

/// Composite goal (AND, OR, SEQUENCE)
pub enum CompositeGoal {
  Single(Goal)
  All(Array[Goal])        // All must be satisfied
  Any(Array[Goal])        // At least one must be satisfied
  Sequence(Array[Goal])   // Must be satisfied in order
}

/// Agent action
pub enum AgentAction {
  /// Execute a shell command
  Exec(String)
  /// Write content to a file
  WriteFile(path~ : String, content~ : String)
  /// Read a file
  ReadFile(String)
  /// Create a directory
  Mkdir(String)
  /// Delete a file or directory
  Remove(String)
  /// Call an external tool via LLM
  ToolCall(name~ : String, args~ : String)
  /// Create a checkpoint
  Checkpoint(String)
  /// Fork to explore an alternative approach
  Fork(branch~ : String, approach~ : String)
  /// Report completion
  Done(String)
  /// Report failure
  Fail(String)
}

/// Agent thought (reasoning step)
pub struct Thought {
  observation : String      // What the agent observed
  reasoning : String        // Why it chose this action
  action : AgentAction      // What action to take
  confidence : Double       // 0.0 - 1.0
}

/// Agent state
pub struct AgentState {
  /// Current step number
  mut step : Int
  /// History of thoughts
  history : Array[Thought]
  /// Current branch name
  mut branch : String?
  /// Snapshot at start of current exploration
  mut checkpoint : @runtime.RuntimeSnapshot?
}

/// Exploration branch
pub struct ExplorationBranch {
  name : String
  approach : String
  state : AgentState
  mut snapshot : @runtime.RuntimeSnapshot
  mut status : BranchStatus
}

/// Branch execution status
pub enum BranchStatus {
  Running
  Succeeded
  Failed(String)
  Abandoned
}

/// Agent configuration
pub struct AgentConfig {
  /// Maximum steps before timeout
  max_steps : Int
  /// Maximum parallel explorations
  max_branches : Int
  /// LLM model to use
  model : String
  /// System prompt
  system_prompt : String
  /// Available tools for the agent
  tools : Array[@llm.Tool]
}

/// Agent execution result
pub struct AgentResult {
  status : GoalStatus
  final_state : AgentState
  branches : Array[ExplorationBranch]
  total_steps : Int
  total_tokens : Int
}

/// Create default agent config
pub fn AgentConfig::default() -> AgentConfig {
  {
    max_steps: 50,
    max_branches: 3,
    model: "anthropic/claude-3.5-sonnet",
    system_prompt: default_system_prompt(),
    tools: default_tools(),
  }
}

/// Default system prompt
fn default_system_prompt() -> String {
  #| You are an autonomous agent working to achieve a goal. You have access to a sandboxed filesystem environment.
  #|
  #| For each step:
  #| 1. Observe the current state
  #| 2. Reason about what action to take
  #| 3. Choose an action from the available tools
  #| 4. If you're unsure, create a checkpoint and try an approach. If it fails, you can rollback.
  #|
  #| Available actions:
  #| - exec: Run a shell command
  #| - write_file: Write content to a file
  #| - read_file: Read a file's contents
  #| - mkdir: Create a directory
  #| - remove: Delete a file or directory
  #| - checkpoint: Save current state
  #| - fork: Create a branch to explore an alternative approach
  #| - done: Report that the goal is achieved
  #| - fail: Report that the goal cannot be achieved
  #|
  #| Always explain your reasoning before taking an action.
}

/// Parse JSON schema or return empty object on error
fn parse_schema(s : String) -> Json {
  try { @json.parse(s) } catch { _ => abort("invalid schema: " + s) }
}

/// Default tools
fn default_tools() -> Array[@llm.Tool] {
  let string_schema = parse_schema(
    #| {"type":"object","properties":{"value":{"type":"string"}},"required":["value"]}
  )
  let file_schema = parse_schema(
    #| {"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}
  )
  let fork_schema = parse_schema(
    #| {"type":"object","properties":{"branch":{"type":"string"},"approach":{"type":"string"}},"required":["branch","approach"]}
  )

  [
    @llm.Tool::function("exec", "Execute a shell command", string_schema),
    @llm.Tool::function("write_file", "Write content to a file", file_schema),
    @llm.Tool::function("read_file", "Read a file's contents", string_schema),
    @llm.Tool::function("mkdir", "Create a directory", string_schema),
    @llm.Tool::function("remove", "Delete a file or directory", string_schema),
    @llm.Tool::function("checkpoint", "Save current state with a message", string_schema),
    @llm.Tool::function("fork", "Create a branch to explore an alternative", fork_schema),
    @llm.Tool::function("done", "Report goal achieved with result", string_schema),
    @llm.Tool::function("fail", "Report goal cannot be achieved with reason", string_schema),
  ]
}

/// Create a goal from a predicate
pub fn Goal::new(
  name : String,
  description : String,
  check : (@runtime.AgentRuntime) -> Bool
) -> Goal {
  { name, description, check }
}

/// File exists goal
pub fn Goal::file_exists(path : String) -> Goal {
  Goal::new(
    "file_exists:" + path,
    "File " + path + " must exist",
    fn(rt) { rt.exists(path) },
  )
}

/// File contains goal
pub fn Goal::file_contains(path : String, content : String) -> Goal {
  Goal::new(
    "file_contains:" + path,
    "File " + path + " must contain: " + content,
    fn(rt) {
      if not(rt.exists(path)) {
        return false
      }
      let file_content = try { rt.read_string(path) } catch { _ => return false }
      file_content.contains(content)
    },
  )
}

/// Directory exists goal
pub fn Goal::dir_exists(path : String) -> Goal {
  Goal::new(
    "dir_exists:" + path,
    "Directory " + path + " must exist",
    fn(rt) { rt.is_dir(path) },
  )
}

/// Custom goal with description
pub fn Goal::custom(
  name : String,
  description : String,
  check : (@runtime.AgentRuntime) -> Bool
) -> Goal {
  { name, description, check }
}

/// Check if goal is achieved
pub fn Goal::is_achieved(self : Goal, rt : @runtime.AgentRuntime) -> Bool {
  (self.check)(rt)
}

/// Check composite goal
pub fn CompositeGoal::is_achieved(
  self : CompositeGoal,
  rt : @runtime.AgentRuntime
) -> Bool {
  match self {
    Single(g) => g.is_achieved(rt)
    All(goals) => {
      for g in goals {
        if not(g.is_achieved(rt)) {
          return false
        }
      }
      true
    }
    Any(goals) => {
      for g in goals {
        if g.is_achieved(rt) {
          return true
        }
      }
      false
    }
    Sequence(goals) => {
      // For sequence, all must be achieved (order is checked during execution)
      for g in goals {
        if not(g.is_achieved(rt)) {
          return false
        }
      }
      true
    }
  }
}

/// Get description of composite goal
pub fn CompositeGoal::description(self : CompositeGoal) -> String {
  match self {
    Single(g) => g.description
    All(goals) => {
      let parts : Array[String] = []
      for g in goals {
        parts.push(g.description)
      }
      "ALL of: [" + parts.iter().fold(init="", fn(acc, s) {
        if acc == "" { s } else { acc + ", " + s }
      }) + "]"
    }
    Any(goals) => {
      let parts : Array[String] = []
      for g in goals {
        parts.push(g.description)
      }
      "ANY of: [" + parts.iter().fold(init="", fn(acc, s) {
        if acc == "" { s } else { acc + ", " + s }
      }) + "]"
    }
    Sequence(goals) => {
      let parts : Array[String] = []
      for g in goals {
        parts.push(g.description)
      }
      "SEQUENCE: [" + parts.iter().fold(init="", fn(acc, s) {
        if acc == "" { s } else { acc + " -> " + s }
      }) + "]"
    }
  }
}
