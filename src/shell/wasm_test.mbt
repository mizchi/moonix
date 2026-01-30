///| Tests for WASM command execution

test "external command without runner returns 127" {
  let sh = ShellContext::new()
  sh.reset_streams()
  let result = sh.exec("nonexistent_command")
  assert_eq(result, 127)
  let stderr = bytes_to_string(sh.get_stderr())
  assert_true(stderr.contains("command not found"))
}

test "external wasm command with runner" {
  let sh = ShellContext::new()

  // Create a mock WASM runner
  let mock_runner : WasmRunnerFn = WasmRunnerFn(
    fn(_wasm_bytes, stdin, _args, _env, _cwd) {
      // Mock: uppercase the input
      let input = bytes_to_str(stdin)
      let output = to_upper(input)
      Ok((0, str_to_bytes(output), Bytes::new(0)))
    }
  )
  sh.set_wasm_runner(mock_runner)

  // Create a fake wasm file in /bin
  sh.get_fs().mkdir_p("/bin")
  sh.get_fs().write_file("/bin/uppercase.wasm", Bytes::new(1))

  // Set up pipe input
  sh.set_pipe_input(str_to_bytes("hello world\n"))

  sh.reset_streams()
  let result = sh.exec("uppercase")
  assert_eq(result, 0)

  let stdout = bytes_to_string(sh.get_stdout())
  assert_eq(stdout, "HELLO WORLD\n")
}

test "external wasm command not found" {
  let sh = ShellContext::new()

  // Set runner but no wasm file
  let mock_runner : WasmRunnerFn = WasmRunnerFn(
    fn(_wasm_bytes, _stdin, _args, _env, _cwd) {
      Ok((0, Bytes::new(0), Bytes::new(0)))
    }
  )
  sh.set_wasm_runner(mock_runner)

  sh.reset_streams()
  let result = sh.exec("nonexistent")
  assert_eq(result, 127)
}

test "wasm command in pipe" {
  let sh = ShellContext::new()

  // Mock runner that reverses lines
  let mock_runner : WasmRunnerFn = WasmRunnerFn(
    fn(_wasm_bytes, stdin, _args, _env, _cwd) {
      let input = bytes_to_str(stdin)
      let reversed = reverse_str(input)
      Ok((0, str_to_bytes(reversed + "\n"), Bytes::new(0)))
    }
  )
  sh.set_wasm_runner(mock_runner)

  // Create wasm command
  sh.get_fs().mkdir_p("/bin")
  sh.get_fs().write_file("/bin/reverse.wasm", Bytes::new(1))

  // Test: echo hello | reverse
  sh.reset_streams()
  let result = sh.exec("echo hello | reverse")
  assert_eq(result, 0)

  let stdout = bytes_to_string(sh.get_stdout())
  assert_true(stdout.contains("olleh"))
}

// Helper functions for tests
fn bytes_to_str(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn str_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}

fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    let code = c.to_int()
    if code >= 97 && code <= 122 {
      buf.write_char((code - 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

fn reverse_str(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    if c != '\n' {
      chars.push(c)
    }
  }
  let buf = StringBuilder::new()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
