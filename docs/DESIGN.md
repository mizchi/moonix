# moonix Design Document

## Vision

moonix is a WASM-based secure shell environment designed for AI agent execution. It combines:

1. **Safe Execution**: Complete isolation from host system
2. **Git-backed State**: Immutable, rollbackable filesystem
3. **Effect Logging**: Audit trail for irreversible operations
4. **Agent Interop**: MCP/A2A protocol support

Inspired by **Unison** (content-addressed code) and **Nix** (reproducible builds).

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Agent Runtime                           │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                 Capability Gate                         │ │
│  │  (only permitted operations pass through)               │ │
│  └────────────────────────────────────────────────────────┘ │
│         │              │              │                      │
│    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐               │
│    │   MCP   │    │   A2A   │    │  HTTP   │               │
│    │ Client  │    │ Protocol│    │ Client  │               │
│    └─────────┘    └─────────┘    └─────────┘               │
│                                                             │
│  ┌─────────────────────┐  ┌──────────────────────────────┐ │
│  │    GitBackedFs      │  │      EffectLog               │ │
│  │    (reversible)     │  │      (irreversible)          │ │
│  └─────────────────────┘  └──────────────────────────────┘ │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  shell │ sh │ posix │ proc │ net │ wasm │ fs              │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. GitBackedFs

Git-backed virtual filesystem that enables snapshots and rollback.

```
┌─────────────────────────────────────────────────────────────┐
│                    GitBackedFs                               │
│  ┌──────────────────┐    ┌─────────────────────────────────┐│
│  │  MemFs           │    │  ObjectStore (.git/objects)      ││
│  │  (working tree)  │◄──►│  - blobs (file contents)         ││
│  │  - current state │    │  - trees (directories)           ││
│  └──────────────────┘    │  - commits (snapshots)           ││
│                          └─────────────────────────────────┘│
│                                                             │
│  Operations:                                                │
│  - snapshot() -> ObjectId    // create commit               │
│  - rollback(ObjectId)        // checkout commit             │
│  - history() -> commits      // list commits                │
│  - branch(name)              // create branch               │
│  - fork() -> new GitBackedFs // clone environment           │
└─────────────────────────────────────────────────────────────┘
```

**Write Strategies:**

| Strategy | Description | Use Case |
|----------|-------------|----------|
| Lazy Commit | MemFs only, batch on snapshot | Fast exploration |
| Eager Commit | Both MemFs + ObjectStore | Full audit trail |
| Hybrid | Mode switching | Flexible |

**Performance Characteristics:**

| Operation | MemFs | GitBackedFs | Notes |
|-----------|-------|-------------|-------|
| write 1KB | ~1μs | ~50μs | SHA-1 + optional zlib |
| write 100KB | ~5μs | ~500μs | Scales with size |
| read | ~1μs | ~1μs | No overhead |
| snapshot | N/A | ~1ms/100 files | Batch tree creation |
| rollback | N/A | ~10ms | Tree traversal |

For AI agents (low write frequency), overhead is acceptable.

### 2. Effect Log

Append-only log for irreversible external effects.

```
┌─────────────────────────────────────────────────────────────┐
│                    Effect Classification                     │
├─────────────────────────────────────────────────────────────┤
│  Reversible (Git管理)          │  Irreversible (Log管理)    │
│  ─────────────────────────────│────────────────────────────│
│  • File create/delete          │  • HTTP POST/PUT/DELETE    │
│  • File content changes        │  • MCP tool calls          │
│  • Directory operations        │  • A2A task delegation     │
│  • Environment variables       │  • External DB writes      │
│                               │  • Message sending          │
│                               │  • Wall clock reads         │
│                               │  • Random generation        │
└─────────────────────────────────────────────────────────────┘
```

**Effect Entry Structure:**

```moonbit
pub struct EffectEntry {
  id : String              // content-addressed hash
  timestamp : Int64        // monotonic clock
  kind : EffectKind
  input : Bytes            // request body / parameters
  output : Bytes           // response body / result
  duration_ns : Int64
  parent_snapshot : String // git commit at execution time
}
```

**WASI Interface Mapping:**

| WASI Interface | Effect Type | Captured Data |
|---------------|-------------|---------------|
| `wasi:http/outgoing-handler` | HttpRequest | URL, method, body, response |
| `wasi:sockets/tcp` | SocketConnect | host, port, data |
| `wasi:clocks/wall-clock` | WallClockRead | returned time |
| `wasi:random/random` | RandomGenerate | bytes generated |
| `wasi:filesystem/*` | (GitBackedFs) | Managed separately |

### 3. Capability-based Security

```moonbit
pub enum Capability {
  // Filesystem
  FsRead(glob: String)       // e.g., /home/** read-only
  FsWrite(glob: String)      // e.g., /tmp/** write-only

  // Network
  NetConnect(hosts: Array[String])  // specific hosts only
  McpCall(tools: Array[String])     // specific tools only

  // A2A
  A2ADelegate(agents: Array[String]) // specific agents only

  // Git operations
  GitSnapshot
  GitRollback
}

pub struct AgentContext {
  capabilities : Array[Capability]
  fs : GitBackedFs
  effect_log : EffectLog
  mcp_clients : Map[String, McpClient]
  a2a_peers : Map[String, AgentCard]
}
```

**Implemented as AgentRuntime (src/runtime/):**

```moonbit
// Create runtime with capability preset
let rt = AgentRuntime::sandbox()  // /tmp only write
let rt = AgentRuntime::developer()  // full access

// Filesystem operations (capability-checked)
rt.write_string("/tmp/file.txt", content)  // allowed in sandbox
rt.write_string("/etc/passwd", content)    // PermissionDenied

// Snapshot with effect tracking
let snap = rt.snapshot("Before experiment")
let _ = rt.http_request("POST", url, body, handler)  // logged
let _ = rt.mcp_call("tool", input, handler)          // logged
let result = rt.rollback(snap)
// result.irreversible_effects contains the HTTP and MCP calls
```

### 4. MCP Integration

```moonbit
// MCP Tool (exposed by this VM)
pub struct McpTool {
  name : String
  description : String
  input_schema : JsonSchema
  handler : (Json) -> Result[Json, McpError]
}

// MCP Client (call external tools)
pub struct McpClient {
  endpoint : String
  capabilities : Array[String]
}
```

### 5. A2A Integration

```moonbit
// Agent Card (self-introduction)
pub struct AgentCard {
  name : String
  description : String
  capabilities : Array[String]
  endpoint : String
  auth : AuthConfig?
}

// A2A Message
pub enum A2AMessage {
  TaskRequest(task_id: String, prompt: String, context: Json)
  TaskResponse(task_id: String, result: Json, artifacts: Array[Artifact])
  StatusUpdate(task_id: String, status: TaskStatus)
  Cancel(task_id: String)
}
```

## Snapshot Structure

```moonbit
pub struct Snapshot {
  fs_commit : String        // Git commit hash
  effect_log_head : String  // Effect log position
  env : Map[String, String] // Environment variables
  cwd : String              // Working directory
  timestamp : Int64
}
```

## Rollback Behavior

```moonbit
pub fn rollback(
  runtime : AgentRuntime,
  target : SnapshotId,
) -> RollbackResult {
  // 1. Filesystem: restored
  runtime.fs.checkout(target.fs_commit)

  // 2. Effects: cannot restore, return warnings
  let effects_after = runtime.effect_log.entries_after(target.effect_log_head)

  RollbackResult::{
    restored_fs: true,
    irreversible_effects: effects_after,
    warning: if effects_after.length() > 0 {
      Some("Warning: {n} external effects cannot be undone")
    } else {
      None
    }
  }
}
```

## Shell Commands

```bash
# Snapshot operations
snapshot "checkpoint name"   # Create snapshot
rollback abc123             # Restore to snapshot
rollback --dry-run abc123   # Preview what would change
history                     # List snapshots

# Effect log
effects                     # List all effects
effects --since abc123      # Effects after snapshot
effects --kind http         # Filter by type

# MCP operations
mcp list                    # Available tools
mcp call tool_name args     # Call tool
mcp serve                   # Expose this VM as MCP server

# A2A operations
a2a discover                # Find peer agents
a2a delegate agent "task"   # Delegate task
a2a status task-123         # Check task status
```

## Example Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  User: "Analyze this file and post results to Slack"        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Agent Runtime (moonix)                                     │
│                                                             │
│  1. snapshot "before analysis"                              │
│  2. cat /data/file.csv | analyze                           │
│  3. mcp call slack_post --channel #results --text "$out"   │
│  4. snapshot "after slack post"                             │
│                                                             │
│  GitBackedFs:                  EffectLog:                   │
│  ├─ commit: abc123             ├─ [mcp slack_post ...]      │
│  └─ /data/analysis.json        └─ parent: abc123            │
└─────────────────────────────────────────────────────────────┘
```

## Dependencies

```
moonix (agent runtime)
├── mizchi/git         # GitBackedFs implementation
├── mcp                # MCP protocol (new)
├── a2a                # A2A protocol (new)
└── json               # Message serialization
```

## Roadmap

### Phase 1: POSIX Shell (Complete)
- [x] 22 built-in commands
- [x] Control structures (if/for/while)
- [x] Pipes and redirects
- [x] Quote handling, glob expansion
- [x] Command substitution, arithmetic expansion

### Phase 2: Git Integration (Complete)
- [x] GitBackedFs implementation (src/gitfs/)
- [x] Snapshot/rollback commands
- [x] Branch support
- [x] History tracking

### Phase 3: Effect Logging & Security (Complete)
- [x] Effect log storage (src/effect/)
- [x] EffectKind: HTTP, MCP, A2A, Socket, Clock, Random, Process
- [x] Capability-based security (src/capability/)
- [x] Capability presets: minimal, sandbox, developer, agent
- [x] AgentRuntime integration (src/runtime/)
- [x] Rollback with irreversible effect warnings

### Phase 4: Agent Interop
- [ ] MCP client/server
- [ ] A2A protocol
- [ ] Runtime integration

## Design Principles

1. **Safety First**: All external effects are explicit and logged
2. **Reproducibility**: Any state can be recreated from snapshot
3. **Auditability**: Complete history of all operations
4. **Capability-based**: No ambient authority, explicit permissions
5. **Content-addressed**: Files identified by hash (like Unison/Nix)
