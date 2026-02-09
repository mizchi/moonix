///|
/// Tests for AgentRuntime
test "AgentRuntime::sandbox creates sandbox runtime" {
  let rt = @runtime.AgentRuntime::sandbox()
  assert_true(rt.exists("/"))
  assert_eq(rt.getcwd(), "/")
}

///|
test "AgentRuntime::read_write with sandbox permissions" {
  let rt = @runtime.AgentRuntime::sandbox()
  rt.set_timestamp_provider(fn() { 1000L })

  // Can write to /tmp
  rt.mkdir_p("/tmp")
  rt.write_string("/tmp/test.txt", "hello")
  let content = rt.read_string("/tmp/test.txt")
  assert_eq(content, "hello")
}

///|
test "AgentRuntime::sandbox denies write outside /tmp" {
  let rt = @runtime.AgentRuntime::sandbox()

  // Cannot write to /etc
  let result = try {
    rt.write_string("/etc/passwd", "hacked")
    Ok(())
  } catch {
    @runtime.PermissionDenied(_) => Err("denied")
    _ => Err("other error")
  }
  assert_true(result is Err(_))
}

///|
test "AgentRuntime::snapshot and rollback" {
  let rt = @runtime.AgentRuntime::developer()
  rt.set_timestamp_provider(fn() { 1000L })

  // Write initial file
  rt.mkdir_p("/home")
  rt.write_string("/home/file.txt", "version 1")
  let snap1 = rt.snapshot("Initial")

  // Modify file
  rt.write_string("/home/file.txt", "version 2")
  assert_eq(rt.read_string("/home/file.txt"), "version 2")

  // Rollback
  let result = rt.rollback(snap1)
  assert_true(result.restored_fs)
  assert_eq(rt.read_string("/home/file.txt"), "version 1")
}

///|
test "AgentRuntime::rollback reports irreversible effects" {
  let rt = @runtime.AgentRuntime::developer()
  let mut ts = 1000L
  rt.set_timestamp_provider(fn() {
    let t = ts
    ts = ts + 100L
    t
  })

  // Create snapshot
  rt.mkdir_p("/home")
  rt.write_string("/home/file.txt", "initial")
  let snap = rt.snapshot("Before effects")

  // Perform irreversible operations
  let _ = rt.wall_clock()
  let _ = rt.random_bytes(16)

  // Rollback
  let result = rt.rollback(snap)
  assert_eq(result.irreversible_effects.length(), 2)
  assert_true(result.warning is Some(_))
}

///|
test "AgentRuntime::mcp_call checks capability" {
  let config = @runtime.RuntimeConfig::agent(
    "test-agent",
    ["file_read", "web_search"],
    [],
    [],
  )
  let rt = @runtime.AgentRuntime::new(config)

  // Allowed tool
  let result = rt.mcp_call("file_read", Some("{}"), fn(_tool, _input) {
    { success: true, output: Some("result"), error: None }
  })
  assert_true(result.success)

  // Denied tool
  let denied = try {
    let _ = rt.mcp_call("shell_exec", None, fn(_, _) {
      { success: true, output: None, error: None }
    })
    Ok(())
  } catch {
    @runtime.PermissionDenied(_) => Err("denied")
    _ => Err("other")
  }
  assert_true(denied is Err(_))
}

///|
test "AgentRuntime::http_request logs effect" {
  let config = @runtime.RuntimeConfig::agent("test-agent", [], [], [
    "api.example.com",
  ])
  let rt = @runtime.AgentRuntime::new(config)
  rt.set_timestamp_provider(fn() { 1000L })

  // Make request
  let response = rt.http_request("GET", "https://api.example.com/data", None, fn(
    _,
    _,
    _,
  ) {
    { status: 200, body: b"response" }
  })
  assert_eq(response.status, 200)

  // Check effect was logged
  let effects = rt.get_http_effects()
  assert_eq(effects.length(), 1)
}

///|
test "AgentRuntime::environment variables" {
  let rt = @runtime.AgentRuntime::developer()

  // Set and get env
  rt.setenv("MY_VAR", "my_value")
  assert_eq(rt.getenv("MY_VAR"), Some("my_value"))

  // Get all env
  let all_env = rt.get_all_env()
  assert_true(all_env.length() > 0)
}

///|
test "AgentRuntime::working directory" {
  let rt = @runtime.AgentRuntime::developer()
  rt.mkdir_p("/home/user")
  assert_eq(rt.getcwd(), "/")
  rt.chdir("/home/user")
  assert_eq(rt.getcwd(), "/home/user")

  // Relative path resolution
  let abs = rt.resolve_path("file.txt")
  assert_eq(abs, "/home/user/file.txt")
}

///|
test "AgentRuntime::has_changes tracks dirty state" {
  let rt = @runtime.AgentRuntime::developer()
  rt.set_timestamp_provider(fn() { 1000L })
  assert_false(rt.has_changes())
  rt.mkdir_p("/home")
  rt.write_string("/home/test.txt", "content")
  assert_true(rt.has_changes())
  let _ = rt.snapshot("Save changes")
  assert_false(rt.has_changes())
}

///|
test "AgentRuntime::history returns commits" {
  let rt = @runtime.AgentRuntime::developer()
  let mut ts = 1000L
  rt.set_timestamp_provider(fn() {
    let t = ts
    ts = ts + 100L
    t
  })
  rt.mkdir_p("/home")
  rt.write_string("/home/a.txt", "a")
  let _ = rt.snapshot("First")
  rt.write_string("/home/b.txt", "b")
  let _ = rt.snapshot("Second")
  let history = rt.history()
  assert_eq(history.length(), 2)
  assert_eq(history[0].message, "Second")
  assert_eq(history[1].message, "First")
}
