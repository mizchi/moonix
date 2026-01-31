///| Agent implementation - autonomous goal-oriented execution

/// Agent error
pub suberror AgentError {
  AgentRuntimeError(String)
  AgentLlmError(String)
  GoalError(String)
  BranchError(String)
}

/// Convert runtime error to string
fn runtime_error_to_string(e : @runtime.RuntimeError) -> String {
  match e {
    @runtime.PermissionDenied(s) => "PermissionDenied: " + s
    @runtime.IoError(s) => "IoError: " + s
    @runtime.GitError(s) => "GitError: " + s
    @runtime.ValidationError(s) => "ValidationError: " + s
  }
}

/// Convert LLM error to string
fn llm_error_to_string(e : @llm.LlmError) -> String {
  match e {
    @llm.HttpError(code, msg) => "HttpError(" + code.to_string() + "): " + msg
    @llm.ParseError(s) => "ParseError: " + s
    @llm.ApiError(s) => "ApiError: " + s
    @llm.RateLimited => "RateLimited"
    @llm.InvalidResponse(s) => "InvalidResponse: " + s
  }
}

/// Autonomous agent
pub struct Agent {
  /// Runtime environment
  runtime : @runtime.AgentRuntime
  /// LLM client
  llm : @llm.OpenRouterClient
  /// HTTP handler for LLM calls
  llm_handler : @llm.LlmHttpHandler
  /// Goal to achieve
  goal : CompositeGoal
  /// Configuration
  config : AgentConfig
  /// Current state
  mut state : AgentState
  /// Active exploration branches
  branches : Array[ExplorationBranch]
  /// Total tokens used
  mut total_tokens : Int
}

/// Create a new agent
pub fn Agent::new(
  runtime : @runtime.AgentRuntime,
  llm : @llm.OpenRouterClient,
  llm_handler : @llm.LlmHttpHandler,
  goal : CompositeGoal,
  config~ : AgentConfig = AgentConfig::default()
) -> Agent {
  {
    runtime,
    llm,
    llm_handler,
    goal,
    config,
    state: { step: 0, history: [], branch: None, checkpoint: None },
    branches: [],
    total_tokens: 0,
  }
}

/// Run the agent until goal is achieved or timeout
pub fn Agent::run(self : Agent) -> AgentResult raise AgentError {
  // Create initial checkpoint
  let initial_snap = self.runtime.snapshot("agent_start") catch {
    e => raise AgentRuntimeError(runtime_error_to_string(e))
  }
  self.state.checkpoint = Some(initial_snap)

  // Main execution loop
  while self.state.step < self.config.max_steps {
    // Check if goal is achieved
    if self.goal.is_achieved(self.runtime) {
      return {
        status: Achieved,
        final_state: self.state,
        branches: self.branches,
        total_steps: self.state.step,
        total_tokens: self.total_tokens,
      }
    }

    // Get next action from LLM
    let thought = self.think()

    // Record thought
    self.state.history.push(thought)
    self.state.step = self.state.step + 1

    // Execute action
    match thought.action {
      Done(result) => {
        // Agent claims goal is achieved
        if self.goal.is_achieved(self.runtime) {
          return {
            status: Achieved,
            final_state: self.state,
            branches: self.branches,
            total_steps: self.state.step,
            total_tokens: self.total_tokens,
          }
        } else {
          // Goal not actually achieved, continue
          continue
        }
      }
      Fail(reason) => {
        return {
          status: Failed(reason),
          final_state: self.state,
          branches: self.branches,
          total_steps: self.state.step,
          total_tokens: self.total_tokens,
        }
      }
      Fork(branch~, approach~) => {
        self.create_branch(branch, approach)
      }
      action => {
        self.execute_action(action)
      }
    }
  }

  // Timeout
  {
    status: Timeout,
    final_state: self.state,
    branches: self.branches,
    total_steps: self.state.step,
    total_tokens: self.total_tokens,
  }
}

/// Think about next action
fn Agent::think(self : Agent) -> Thought raise AgentError {
  // Build observation
  let observation = self.build_observation()

  // Build messages
  let messages : Array[@llm.Message] = []
  messages.push(@llm.Message::system(self.config.system_prompt))

  // Add goal description
  let goal_msg = "GOAL: " + self.goal.description() + "\n\nCurrent step: " + self.state.step.to_string()
  messages.push(@llm.Message::user(goal_msg))

  // Add history (last few thoughts)
  let history_start = if self.state.history.length() > 5 {
    self.state.history.length() - 5
  } else {
    0
  }
  for i = history_start; i < self.state.history.length(); i = i + 1 {
    let t = self.state.history[i]
    let thought_msg = "Step " + i.to_string() + ":\nObservation: " + t.observation + "\nReasoning: " + t.reasoning
    messages.push(@llm.Message::assistant(thought_msg))
  }

  // Add current observation
  messages.push(@llm.Message::user("Current observation:\n" + observation + "\n\nWhat action should you take next?"))

  // Call LLM
  let response = self.llm.chat(
    messages,
    self.llm_handler,
    tools=Some(self.config.tools),
    model=Some(self.config.model),
  ) catch {
    e => raise AgentLlmError(llm_error_to_string(e))
  }

  // Track tokens
  match response.usage {
    Some(u) => self.total_tokens = self.total_tokens + u.total_tokens
    None => ()
  }

  // Parse response
  if response.choices.length() == 0 {
    raise AgentLlmError("No response from LLM")
  }

  let choice = response.choices[0]
  let msg = choice.message

  // Check for tool calls
  match msg.tool_calls {
    Some(calls) if calls.length() > 0 => {
      let call = calls[0]
      let action = parse_tool_call(call)
      {
        observation,
        reasoning: msg.content,
        action,
        confidence: 0.8,
      }
    }
    _ => {
      // No tool call, parse from content
      {
        observation,
        reasoning: msg.content,
        action: Done("Completed based on reasoning"),
        confidence: 0.5,
      }
    }
  }
}

/// Get empty JSON object
fn empty_json() -> Json {
  // "{}" is always valid JSON, so this will never fail
  try { @json.parse("{}") } catch { _ => abort("impossible: {} is valid JSON") }
}

/// Parse tool call into action
fn parse_tool_call(call : @llm.ToolCall) -> AgentAction {
  let args : Json = try {
    @json.parse(call.function.arguments)
  } catch {
    _ => empty_json()
  }

  match call.function.name {
    "exec" => {
      let cmd = get_json_string(args, "value")
      Exec(cmd)
    }
    "write_file" => {
      let path = get_json_string(args, "path")
      let content = get_json_string(args, "content")
      WriteFile(path~, content~)
    }
    "read_file" => {
      let path = get_json_string(args, "value")
      ReadFile(path)
    }
    "mkdir" => {
      let path = get_json_string(args, "value")
      Mkdir(path)
    }
    "remove" => {
      let path = get_json_string(args, "value")
      Remove(path)
    }
    "checkpoint" => {
      let msg = get_json_string(args, "value")
      Checkpoint(msg)
    }
    "fork" => {
      let branch = get_json_string(args, "branch")
      let approach = get_json_string(args, "approach")
      Fork(branch~, approach~)
    }
    "done" => {
      let result = get_json_string(args, "value")
      Done(result)
    }
    "fail" => {
      let reason = get_json_string(args, "value")
      Fail(reason)
    }
    _ => Done("Unknown action: " + call.function.name)
  }
}

/// Get string from JSON object
fn get_json_string(json : Json, key : String) -> String {
  match json {
    Object(obj) => {
      match obj.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    }
    _ => ""
  }
}

/// Build current observation
fn Agent::build_observation(self : Agent) -> String {
  let buf = StringBuilder::new()

  // Current directory
  buf.write_string("Working directory: ")
  buf.write_string(self.runtime.getcwd())
  buf.write_string("\n")

  // List files in current directory
  let files = try {
    self.runtime.readdir(self.runtime.getcwd())
  } catch {
    _ => []
  }
  buf.write_string("Files: ")
  for i, f in files {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(f.name)
  }
  buf.write_string("\n")

  // Goal status
  buf.write_string("Goal achieved: ")
  buf.write_string(self.goal.is_achieved(self.runtime).to_string())
  buf.write_string("\n")

  // Branch info
  match self.state.branch {
    Some(b) => {
      buf.write_string("Current branch: ")
      buf.write_string(b)
      buf.write_string("\n")
    }
    None => ()
  }

  buf.to_string()
}

/// Execute an action
fn Agent::execute_action(self : Agent, action : AgentAction) -> Unit raise AgentError {
  match action {
    Exec(cmd) => {
      // Note: In WASM environment, exec is not directly available
      // This would need to be handled by the host
      ()
    }
    WriteFile(path~, content~) => {
      // Ensure parent directory exists
      let parts = path.split("/").collect()
      if parts.length() > 1 {
        let dir_parts : Array[String] = []
        for i = 0; i < parts.length() - 1; i = i + 1 {
          dir_parts.push(parts[i].to_string())
        }
        let dir = dir_parts.iter().fold(init="", fn(acc, s) {
          if acc == "" { s } else { acc + "/" + s }
        })
        if dir != "" {
          self.runtime.mkdir_p(dir) catch {
            e => raise AgentRuntimeError(runtime_error_to_string(e))
          }
        }
      }
      self.runtime.write_string(path, content) catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }
    }
    ReadFile(path) => {
      // Just read, result is in observation
      let _ = self.runtime.read_string(path) catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }

    }
    Mkdir(path) => {
      self.runtime.mkdir_p(path) catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }
    }
    Remove(path) => {
      self.runtime.rm_rf(path) catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }
    }
    Checkpoint(msg) => {
      let snap = self.runtime.snapshot(msg) catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }
      self.state.checkpoint = Some(snap)
    }
    Fork(branch~, approach~) => {
      self.create_branch(branch, approach)
    }
    ToolCall(name~, args~) => {
      // External tool call - would be handled by MCP in a full implementation
      let _ = name
      let _ = args
      ()
    }
    Done(_) | Fail(_) => {
      // Handled in main loop
      ()
    }
  }
}

/// Create a new exploration branch
fn Agent::create_branch(
  self : Agent,
  name : String,
  approach : String
) -> Unit raise AgentError {
  if self.branches.length() >= self.config.max_branches {
    // Too many branches, abandon oldest non-successful one
    let mut abandoned = false
    for i = 0; i < self.branches.length(); i = i + 1 {
      match self.branches[i].status {
        Running | Failed(_) => {
          self.branches[i].status = Abandoned
          abandoned = true
          break
        }
        _ => ()
      }
    }
    if not(abandoned) {
      raise BranchError("Cannot create more branches")
    }
  }

  // Get current checkpoint or create one
  let snap = match self.state.checkpoint {
    Some(s) => s
    None => {
      let s = self.runtime.snapshot("branch_point") catch {
        e => raise AgentRuntimeError(runtime_error_to_string(e))
      }
      self.state.checkpoint = Some(s)
      s
    }
  }

  // Create branch
  let branch : ExplorationBranch = {
    name,
    approach,
    state: {
      step: self.state.step,
      history: [], // Start fresh history for branch
      branch: Some(name),
      checkpoint: Some(snap),
    },
    snapshot: snap,
    status: Running,
  }
  self.branches.push(branch)

  // Fork in runtime
  self.runtime.fork(snap, name) catch {
    e => raise AgentRuntimeError(runtime_error_to_string(e))
  }

  // Update current branch
  self.state.branch = Some(name)
}

/// Run agent in parallel exploration mode
pub fn Agent::run_parallel(
  self : Agent,
  approaches : Array[String]
) -> AgentResult raise AgentError {
  // Create initial checkpoint
  let initial_snap = self.runtime.snapshot("parallel_start") catch {
    e => raise AgentRuntimeError(runtime_error_to_string(e))
  }
  self.state.checkpoint = Some(initial_snap)

  // Create branches for each approach
  for i, approach in approaches {
    if i >= self.config.max_branches {
      break
    }
    let branch_name = "approach_" + i.to_string()
    let branch : ExplorationBranch = {
      name: branch_name,
      approach,
      state: {
        step: 0,
        history: [],
        branch: Some(branch_name),
        checkpoint: Some(initial_snap),
      },
      snapshot: initial_snap,
      status: Running,
    }
    self.branches.push(branch)
  }

  // Run branches in round-robin until one succeeds or all fail
  while true {
    let mut all_done = true
    let mut any_running = false

    for i = 0; i < self.branches.length(); i = i + 1 {
      match self.branches[i].status {
        Running => {
          any_running = true
          all_done = false

          // Switch to this branch
          self.runtime.fork(self.branches[i].snapshot, self.branches[i].name) catch {
            e => {
              self.branches[i].status = Failed(runtime_error_to_string(e))
              continue
            }
          }

          // Run one step
          let step_result = self.run_one_step(i)
          match step_result {
            Achieved => {
              self.branches[i].status = Succeeded
              return {
                status: Achieved,
                final_state: self.branches[i].state,
                branches: self.branches,
                total_steps: self.state.step,
                total_tokens: self.total_tokens,
              }
            }
            Failed(reason) => {
              self.branches[i].status = Failed(reason)
            }
            Timeout => {
              self.branches[i].status = Failed("Timeout")
            }
            InProgress => {
              // Save state back
              let snap = self.runtime.snapshot("step_" + self.branches[i].state.step.to_string()) catch {
                _ => self.branches[i].snapshot
              }
              self.branches[i].snapshot = snap
            }
          }
        }
        _ => ()
      }
    }

    if not(any_running) || all_done {
      break
    }
  }

  // All branches done without success
  {
    status: Failed("All approaches failed"),
    final_state: self.state,
    branches: self.branches,
    total_steps: self.state.step,
    total_tokens: self.total_tokens,
  }
}

/// Run one step for a branch
fn Agent::run_one_step(self : Agent, branch_idx : Int) -> GoalStatus raise AgentError {
  let branch = self.branches[branch_idx]

  // Check step limit
  if branch.state.step >= self.config.max_steps {
    return Timeout
  }

  // Check if goal is achieved
  if self.goal.is_achieved(self.runtime) {
    return Achieved
  }

  // Think
  self.state = branch.state
  let thought = self.think()

  // Update branch state
  self.branches[branch_idx].state.history.push(thought)
  self.branches[branch_idx].state.step = self.branches[branch_idx].state.step + 1
  self.state.step = self.state.step + 1

  // Execute
  match thought.action {
    Done(_) => {
      if self.goal.is_achieved(self.runtime) {
        Achieved
      } else {
        InProgress
      }
    }
    Fail(reason) => Failed(reason)
    action => {
      self.execute_action(action)
      InProgress
    }
  }
}
