///| WASI Shell - moonix core + WASI I/O boundary only

pub fn run() -> Result[Unit, Unit] {
  // Initialize WASI stderr early (workaround for initialization issue)
  let stderr_stream = @stderr.get_stderr()
  let _ = @streams.output_stream_blocking_write_and_flush(stderr_stream, [])

  // 1. Use moonix core MemFs directly (no WASI filesystem)
  let fs = @moonix_fs.MemFs::new()

  // 2. Build ShellContext with moonix core
  let sh = @shell.ShellContext::with_fs(fs)

  // 3. Import environment variables from WASI
  let env_vars = @environment.get_environment()
  for kv in env_vars {
    let (key, value) = kv
    sh.get_ctx().setenv(key, value)
  }

  // 4. Read all stdin via WASI
  let stdin_stream = @stdin.get_stdin()
  let all_input = match @streams.input_stream_blocking_read(stdin_stream, 1048576UL) {
    Ok(bytes) => bytes
    Err(_) => return Ok(())
  }

  if all_input.length() == 0 {
    return Ok(())
  }

  // 5. Execute shell script
  let input_str = bytes_array_to_string(all_input)
  let lines = split_lines(input_str)

  let stdout_stream = @stdout.get_stdout()

  for line in lines {
    if line.is_empty() {
      continue
    }
    // Note: Don't call reset_streams() - it breaks stdout capture in WASI context
    let _ = sh.exec_script(line)

    // 6. Write output via WASI stdout/stderr
    let out = sh.get_stdout()
    if out.length() > 0 {
      let _ = @streams.output_stream_blocking_write_and_flush(
        stdout_stream,
        moonbit_bytes_to_array(out)
      )
    }
    let err_out = sh.get_stderr()
    if err_out.length() > 0 {
      let _ = @streams.output_stream_blocking_write_and_flush(
        stderr_stream,
        moonbit_bytes_to_array(err_out)
      )
    }
  }

  Ok(())
}

fn bytes_array_to_string(bytes : Array[Byte]) -> String {
  let buf = StringBuilder::new()
  for b in bytes {
    buf.write_char(b.to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn moonbit_bytes_to_array(b : Bytes) -> Array[Byte] {
  let arr : Array[Byte] = Array::new(capacity=b.length())
  for byte in b {
    arr.push(byte)
  }
  arr
}

fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current = StringBuilder::new()
  for c in s {
    if c == '\n' {
      lines.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  let last = current.to_string()
  if not(last.is_empty()) {
    lines.push(last)
  }
  lines
}

