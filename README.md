# moonix

WASM-based secure shell environment for MoonBit.

## Design Philosophy

### Safe Execution for Vibe Coding

moonix is designed primarily for **safe code execution in AI-assisted development (vibe coding)**. When AI generates and executes code, security is paramount. moonix provides:

- **Complete Isolation**: All filesystem operations run in-memory, never touching the host system
- **Capability-based Security**: No ambient authority; all resources must be explicitly granted
- **Deterministic Execution**: Same inputs always produce same outputs
- **Resource Limits**: Bounded execution time and memory usage

### Future Vision: Immutable Shell

Inspired by **Unison** (content-addressed code) and **Nix** (reproducible builds), moonix aims to evolve into a shell superset language with:

```
┌─────────────────────────────────────────────────────────────┐
│  moonix shell (superset)                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  POSIX sh (compatible subset)                         │  │
│  │  - Pipes, redirects, control flow                     │  │
│  │  - Environment variables                              │  │
│  └───────────────────────────────────────────────────────┘  │
│  + Content-addressed commands (like Unison)                 │
│  + Immutable environments (like Nix)                        │
│  + First-class WASM modules                                 │
│  + Typed pipelines                                          │
└─────────────────────────────────────────────────────────────┘
```

**Key Concepts:**

1. **Content-Addressed Commands**: Commands are identified by their content hash, ensuring reproducibility
2. **Immutable Environments**: Environment snapshots are versioned and can be restored
3. **WASM-First**: All external commands are WASM modules with explicit capability requirements
4. **Gradual Typing**: Start with dynamic shell scripts, add types for reliability

## Architecture

```
┌─────────────┐
│   shell     │  High-level shell execution
├─────────────┤
│   sh        │  Shell parser & AST
├─────────────┤
│   posix     │  POSIX context (fd, env, cwd)
├─────────────┤
│   fs        │  Virtual filesystem (pluggable backend)
├─────────────┤
│   proc      │  Process scheduler & IPC
├─────────────┤
│   net       │  Virtual network & HTTP
├─────────────┤
│   wasm      │  WASM module execution
└─────────────┘
```

## Current Features

### Shell (`@shell`)

22 built-in commands:

| Category | Commands |
|----------|----------|
| I/O | `echo`, `cat`, `head`, `tail`, `grep` |
| Files | `ls`, `touch`, `rm`, `cp`, `mv`, `write` |
| Dirs | `pwd`, `cd`, `mkdir` |
| Env | `env`, `export` |
| Control | `true`, `false`, `exit`, `sleep`, `test`, `[` |

Control structures via `exec_script()`:
- `if/then/elif/else/fi`
- `for x in ...; do ...; done`
- `while/until`
- Pipes (`|`) and redirects (`>`, `>>`)
- Logical operators (`&&`, `||`, `;`)

### Virtual FileSystem (`@fs`)

- `FileSystemBackend` trait for pluggable storage
- `MemFs` - In-memory inode-based filesystem
- Future: IndexedDB, host fs adapters

### POSIX Emulation (`@posix`)

- File descriptors (open, read, write, close, lseek)
- Environment variables
- Working directory
- Pluggable stream handlers

### Process Management (`@proc`)

- Cooperative multitasking scheduler
- Semaphore-based synchronization
- Signal handling (SIGTERM, SIGKILL, etc.)

### Network (`@net`)

- Virtual socket layer
- HTTP request/response parsing
- Virtual network for testing

## Installation

```bash
moon add mizchi/moonix
```

## Usage

### Basic Shell

```moonbit
let sh = @shell.ShellContext::new()

// Execute commands
sh.exec("echo hello world")
sh.exec("mkdir -p /home/user")
sh.exec("echo content > /home/user/file.txt")
sh.exec("cat /home/user/file.txt")

// Get output
let stdout = sh.get_stdout()
```

### Shell Scripts

```moonbit
let sh = @shell.ShellContext::new()

// Control flow
sh.exec_script("
  if test -d /home; then
    echo 'home exists'
  else
    mkdir /home
  fi
")

// Loops
sh.exec_script("
  for f in a b c; do
    touch /tmp/$f.txt
  done
")
```

### Custom FileSystem Backend

```moonbit
// Implement FileSystemBackend trait for your storage
pub impl @fs.FileSystemBackend for MyStorage with read_file(self, path) {
  // Your implementation
}

// Use with PosixContext
let ctx = @posix.PosixContext::new(my_storage, streams)
```

### WASM Command Execution

```moonbit
let sh = @shell.ShellContext::new()

// Register WASM runner
sh.set_wasm_runner(@shell.WasmRunnerFn(fn(wasm, stdin, args, env, cwd) {
  // Execute WASM with your runtime
  Ok((0, output_bytes, error_bytes))
}))

// Place WASM at /bin/mycommand.wasm
sh.get_fs().write_file("/bin/mycommand.wasm", wasm_bytes)

// Execute
sh.exec("mycommand arg1 arg2")
```

## Roadmap

### Phase 1: POSIX Compatibility (Complete)
- [x] Basic shell commands (22 built-ins)
- [x] Control structures (if/for/while)
- [x] Pipes and redirects
- [x] Virtual filesystem
- [x] Quote handling (single/double quotes, escapes)
- [x] Glob expansion (*, ?, [...])
- [x] Command substitution `$()`
- [x] Arithmetic expansion `$(())`

### Phase 2: WASM Integration
- [ ] WASI preview2 support
- [ ] Capability-based permissions
- [ ] Module caching by content hash

### Phase 3: Immutable Shell
- [ ] Content-addressed command store
- [ ] Environment snapshots
- [ ] Typed pipeline DSL
- [ ] Nix-style derivations

## Use Cases

- **AI Sandbox**: Safe execution environment for AI-generated code
- **Browser Playground**: Interactive shell in the browser
- **Reproducible Scripts**: Hermetic builds with WASM
- **Testing**: Isolated filesystem for unit tests

## License

MIT
