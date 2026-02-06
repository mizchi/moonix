///| WASI Shell REPL - executes shell commands via WASI interfaces

pub fn run() -> Result[Unit, Unit] {
  // 1. Get root descriptor from preopens
  let dirs = @preopens.get_directories()
  if dirs.length() == 0 {
    return Err(())
  }
  let (root_desc, _) = dirs[0]

  // 2. Build WasiFs (FileSystemBackend over WASI)
  let wasi_fs = @wasi_fs.WasiFs::new(root_desc)

  // 3. Build WasiStreamHandler (StdStreamHandler over WASI)
  let stream_handler = @wasi_streams.WasiStreamHandler::new()

  // 4. Build ShellContext
  let sh = @shell.ShellContext::with_fs(wasi_fs)

  // 5. Import environment variables from WASI
  let env_vars = @environment.get_environment()
  for kv in env_vars {
    let (key, value) = kv
    sh.get_ctx().setenv(key, value)
  }

  // 6. Override streams with WasiStreamHandler
  // Reset streams to use WASI streams instead of buffered
  let ctx = @posix.PosixContext::new(wasi_fs, stream_handler)
  // Preserve env
  for kv in env_vars {
    let (key, value) = kv
    ctx.setenv(key, value)
  }

  // 7. REPL loop - read from stdin, execute, loop
  let stdin_stream = @stdin.get_stdin()
  let stdout_stream = @stdout.get_stdout()

  // Read all stdin at once and process line by line
  let all_input = match @streams.input_stream_blocking_read(stdin_stream, 1048576UL) {
    Ok(bytes) => bytes
    Err(_) => return Ok(())
  }

  if all_input.length() == 0 {
    return Ok(())
  }

  // Convert to string
  let input_str = bytes_array_to_string(all_input)

  // Split into lines and execute each
  let lines = split_lines(input_str)
  for line in lines {
    if line.is_empty() {
      continue
    }
    // Reset streams for each command to capture output
    sh.reset_streams()
    let _ = sh.exec_script(line)
    // Write captured stdout to WASI stdout
    let out = sh.get_stdout()
    if out.length() > 0 {
      let out_arr = moonbit_bytes_to_array(out)
      match @streams.output_stream_blocking_write_and_flush(stdout_stream, out_arr) {
        Ok(_) => ()
        Err(_) => ()
      }
    }
    // Write captured stderr to WASI stderr
    let err_out = sh.get_stderr()
    if err_out.length() > 0 {
      let err_arr = moonbit_bytes_to_array(err_out)
      let stderr_stream = @stderr.get_stderr()
      match @streams.output_stream_blocking_write_and_flush(stderr_stream, err_arr) {
        Ok(_) => ()
        Err(_) => ()
      }
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
