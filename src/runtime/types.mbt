///| Agent Runtime - integrates GitBackedFs, EffectLog, and Capability control

/// Error type for runtime operations
pub suberror RuntimeError {
  PermissionDenied(String)
  IoError(String)
  GitError(String)
  ValidationError(String)
}

/// Snapshot state for rollback
pub struct RuntimeSnapshot {
  /// Git commit ID
  git_snapshot : @gitfs.SnapshotId
  /// Effect log position at snapshot time
  effect_log_head : Int
  /// Environment variables
  env : Map[String, String]
  /// Working directory
  cwd : String
}

/// Rollback result
pub struct RollbackResult {
  /// Whether filesystem was restored
  restored_fs : Bool
  /// Effects that occurred after the snapshot (cannot be undone)
  irreversible_effects : Array[@effect.EffectEntry]
  /// Warning message if there were irreversible effects
  warning : String?
}

/// Agent runtime configuration
pub struct RuntimeConfig {
  /// Author name for git commits
  author : String
  /// Initial capabilities
  capabilities : @capability.CapabilitySet
}

/// Default configuration
pub fn RuntimeConfig::default() -> RuntimeConfig {
  {
    author: "moonix-agent",
    capabilities: @capability.CapabilitySet::sandbox(),
  }
}

/// Developer configuration (more permissive)
pub fn RuntimeConfig::developer() -> RuntimeConfig {
  {
    author: "moonix-developer",
    capabilities: @capability.CapabilitySet::developer(),
  }
}

/// Agent configuration with specific permissions
pub fn RuntimeConfig::agent(
  author : String,
  mcp_tools : Array[String],
  a2a_agents : Array[String],
  allowed_hosts : Array[String]
) -> RuntimeConfig {
  {
    author,
    capabilities: @capability.CapabilitySet::agent(mcp_tools, a2a_agents, allowed_hosts),
  }
}
