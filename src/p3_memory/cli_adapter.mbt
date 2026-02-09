///|
pub struct CliAdapter {
  kernel : Kernel
}

///|
pub fn CliAdapter::new(kernel : Kernel) -> CliAdapter {
  { kernel, }
}

///|
pub impl @p3.WasiStdinAdapter for CliAdapter with read_via_stream(self) {
  let remaining = self.kernel.stdin_data.length() - self.kernel.stdin_pos
  if remaining <= 0 {
    Ok(b"")
  } else {
    let result : Array[Byte] = []
    for i = self.kernel.stdin_pos
        i < self.kernel.stdin_data.length()
        i = i + 1 {
      result.push(self.kernel.stdin_data[i])
    }
    self.kernel.stdin_pos = self.kernel.stdin_data.length()
    Ok(Bytes::from_iter(result.iter()))
  }
}

///|
pub impl @p3.WasiStdoutAdapter for CliAdapter with write_via_stream(self, data) {
  for b in data {
    self.kernel.stdout_buf.push(b)
  }
  Ok(Ok(()))
}

///|
pub impl @p3.WasiStderrAdapter for CliAdapter with write_via_stream(self, data) {
  for b in data {
    self.kernel.stderr_buf.push(b)
  }
  Ok(Ok(()))
}

///|
pub impl @p3.WasiExitAdapter for CliAdapter with exit(self, status) {
  match status {
    Ok(_) => self.kernel.exit_code = Some(0)
    Err(_) => self.kernel.exit_code = Some(1)
  }
  Ok(())
}

///|
pub impl @p3.WasiExitAdapter for CliAdapter with exit_with_code(self, code) {
  self.kernel.exit_code = Some(code.to_int())
  Ok(())
}

///|
pub impl @p3.WasiEnvironmentAdapter for CliAdapter with get_environment(self) {
  let result : Array[Bytes] = []
  for k, v in self.kernel.env {
    let entry = k + "=" + v
    let bytes : Array[Byte] = []
    for i = 0; i < entry.length(); i = i + 1 {
      bytes.push(entry[i].to_int().to_byte())
    }
    result.push(Bytes::from_iter(bytes.iter()))
  }
  Ok(result)
}

///|
pub impl @p3.WasiEnvironmentAdapter for CliAdapter with get_arguments(self) {
  Ok(self.kernel.args)
}

///|
pub impl @p3.WasiEnvironmentAdapter for CliAdapter with get_initial_cwd(self) {
  Ok(Some(self.kernel.cwd))
}

///|
pub impl @p3.WasiTerminalStdinAdapter for CliAdapter with get_terminal_stdin(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiTerminalStdoutAdapter for CliAdapter with get_terminal_stdout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiTerminalStderrAdapter for CliAdapter with get_terminal_stderr(
  _self,
) {
  Ok(None)
}
