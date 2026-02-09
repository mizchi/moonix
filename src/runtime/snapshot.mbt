///| Snapshot and rollback operations for AgentRuntime

///|
/// Create a snapshot of current state
pub fn AgentRuntime::snapshot(
  self : AgentRuntime,
  message : String,
) -> RuntimeSnapshot raise RuntimeError {
  if not(self.capabilities.can_snapshot()) {
    raise PermissionDenied("snapshot")
  }

  // Create git snapshot
  let git_snapshot = self.fs.snapshot(message) catch {
    e => raise GitError(e.to_string())
  }

  // Record effect log position
  let effect_log_head = self.effect_log.head()

  // Update effect log's current snapshot
  self.effect_log.set_current_snapshot(Some(git_snapshot.commit_id.to_hex()))

  // Copy environment
  let env : Map[String, String] = {}
  for k, v in self.env {
    env.set(k, v)
  }
  { git_snapshot, effect_log_head, env, cwd: self.cwd }
}

///|
/// Rollback to a previous snapshot
pub fn AgentRuntime::rollback(
  self : AgentRuntime,
  snapshot : RuntimeSnapshot,
) -> RollbackResult raise RuntimeError {
  if not(self.capabilities.can_rollback()) {
    raise PermissionDenied("rollback")
  }

  // Get effects that occurred after the snapshot
  let irreversible_effects = self.effect_log.entries_after(
    snapshot.effect_log_head,
  )

  // Rollback filesystem
  self.fs.rollback(snapshot.git_snapshot) catch {
    e => raise GitError(e.to_string())
  }

  // Restore environment
  // Clear current env and restore from snapshot
  let keys : Array[String] = []
  for k, _ in self.env {
    keys.push(k)
  }
  for k in keys {
    self.env.remove(k)
  }
  for k, v in snapshot.env {
    self.env.set(k, v)
  }

  // Restore working directory
  self.cwd = snapshot.cwd

  // Generate warning if there were irreversible effects
  let warning = if irreversible_effects.length() > 0 {
    let count = irreversible_effects.length()
    Some("Warning: \{count} external effect(s) cannot be undone")
  } else {
    None
  }
  { restored_fs: true, irreversible_effects, warning }
}

///|
/// Get commit history
pub fn AgentRuntime::history(
  self : AgentRuntime,
  max_count? : Int = 100,
) -> Array[@gitfs.SnapshotId] raise RuntimeError {
  self.fs.history(max_count~) catch {
    e => raise GitError(e.to_string())
  }
}

///|
/// Create a branch
pub fn AgentRuntime::branch(
  self : AgentRuntime,
  name : String,
) -> Unit raise RuntimeError {
  if not(
      self.capabilities.has(fn(cap) {
        match cap {
          @capability.GitBranch => true
          _ => false
        }
      }),
    ) {
    raise PermissionDenied("branch")
  }
  self.fs.branch(name) catch {
    e => raise GitError(e.to_string())
  }
}

///|
/// Switch to a branch
pub fn AgentRuntime::switch_branch(
  self : AgentRuntime,
  name : String,
) -> Unit raise RuntimeError {
  if not(self.capabilities.can_rollback()) {
    raise PermissionDenied("switch")
  }
  self.fs.switch(name) catch {
    e => raise GitError(e.to_string())
  }
}

///|
/// List branches
pub fn AgentRuntime::list_branches(
  self : AgentRuntime,
) -> Array[String] raise RuntimeError {
  self.fs.list_branches() catch {
    e => raise GitError(e.to_string())
  }
}

///|
/// Fork from a snapshot to a new branch
/// Creates a new branch at the snapshot point and switches to it
pub fn AgentRuntime::fork(
  self : AgentRuntime,
  snapshot : RuntimeSnapshot,
  branch_name : String,
) -> Unit raise RuntimeError {
  if not(self.capabilities.can_rollback()) {
    raise PermissionDenied("fork")
  }
  if not(
      self.capabilities.has(fn(cap) {
        match cap {
          @capability.GitBranch => true
          _ => false
        }
      }),
    ) {
    raise PermissionDenied("branch")
  }

  // Create branch at the snapshot commit
  self.fs.branch_at(branch_name, snapshot.git_snapshot.commit_id) catch {
    e => raise GitError(e.to_string())
  }

  // Rollback to the snapshot state
  self.fs.rollback(snapshot.git_snapshot) catch {
    e => raise GitError(e.to_string())
  }

  // Switch to the new branch
  self.fs.switch(branch_name) catch {
    e => raise GitError(e.to_string())
  }

  // Restore environment and cwd from snapshot
  let keys : Array[String] = []
  for k, _ in self.env {
    keys.push(k)
  }
  for k in keys {
    self.env.remove(k)
  }
  for k, v in snapshot.env {
    self.env.set(k, v)
  }
  self.cwd = snapshot.cwd
}

///|
/// Fork from current state to a new branch
/// Commits current changes if any, then creates a new branch
pub fn AgentRuntime::fork_here(
  self : AgentRuntime,
  branch_name : String,
  message? : String = "fork point",
) -> RuntimeSnapshot raise RuntimeError {
  if not(
      self.capabilities.has(fn(cap) {
        match cap {
          @capability.GitBranch => true
          _ => false
        }
      }),
    ) {
    raise PermissionDenied("branch")
  }

  // Create snapshot of current state
  let snap = self.snapshot(message)

  // Create branch at current HEAD
  self.fs.branch(branch_name) catch {
    e => raise GitError(e.to_string())
  }

  // Switch to the new branch
  self.fs.switch(branch_name) catch {
    e => raise GitError(e.to_string())
  }
  snap
}

///|
/// Get current branch name
pub fn AgentRuntime::current_branch(
  self : AgentRuntime,
) -> String? raise RuntimeError {
  self.fs.current_branch() catch {
    e => raise GitError(e.to_string())
  }
}

///|
/// Check if there are uncommitted changes
pub fn AgentRuntime::has_changes(self : AgentRuntime) -> Bool {
  self.fs.has_changes()
}

///|
/// Get list of changed files
pub fn AgentRuntime::get_dirty_paths(self : AgentRuntime) -> Array[String] {
  self.fs.get_dirty_paths()
}
