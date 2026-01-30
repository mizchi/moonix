# moonix

Virtual POSIX layer for MoonBit - Unix-like filesystem and process emulation for WebAssembly.

## Features

- **Virtual FileSystem**: In-memory filesystem with `FileSystemBackend` trait
- **POSIX Emulation**: File descriptors, environment variables, working directory
- **Stream Handling**: Pluggable stdin/stdout/stderr handlers

## Installation

```bash
moon add mizchi/moonix
```

## Usage

```moonbit
// Create in-memory filesystem
let fs = @fs.MemFs::new()

// Create POSIX context with buffered streams
let streams = @posix.BufferedStreamHandler::new()
let ctx = @posix.PosixContext::new(fs, streams)

// File operations
let fd = ctx.open("/hello.txt", @posix.OpenFlags::create_write())
ctx.write(fd, b"Hello, moonix!")
ctx.close(fd)

// Read back
let fd2 = ctx.open("/hello.txt", @posix.OpenFlags::default())
let content = ctx.read(fd2, 1024)
ctx.close(fd2)

// Environment and working directory
ctx.setenv("HOME", "/home/user")
ctx.chdir("/home/user")
println(ctx.getcwd())  // "/home/user"
```

## Packages

### `@fs` - Virtual FileSystem

- `FileSystemBackend` - Trait for filesystem implementations
- `MemFs` - In-memory filesystem (inode-based)
- `FsError` - Filesystem errors
- Path utilities: `normalize_path`, `parent_path`, `basename`

### `@posix` - POSIX Emulation

- `PosixContext` - Main interface (open, read, write, close, lseek, chdir, etc.)
- `StdStreamHandler` - Trait for stream handling
- `BufferedStreamHandler` - In-memory stream buffer
- `NullStreamHandler` - Discard output, empty input
- `OpenFlags` - File open mode flags
- `PosixError` - POSIX error codes (ENOENT, EEXIST, etc.)

## Use Cases

- **Browser Sandboxes**: Code playground with virtual filesystem
- **WASI Components**: Deploy as OCI containers
- **Testing**: Isolated filesystem for unit tests

## License

MIT
