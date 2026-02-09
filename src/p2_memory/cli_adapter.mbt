///|
pub struct CliAdapter {
  kernel : Kernel
}

///|
pub fn CliAdapter::new(kernel : Kernel) -> CliAdapter {
  { kernel, }
}

///|
pub impl @p2.WasiCliStdinAdapter for CliAdapter with get_stdin(_self) {
  Ok(@p2.CliStdinInputStream(0))
}

///|
pub impl @p2.WasiCliStdoutAdapter for CliAdapter with get_stdout(_self) {
  Ok(@p2.CliStdoutOutputStream(1))
}

///|
pub impl @p2.WasiCliStderrAdapter for CliAdapter with get_stderr(_self) {
  Ok(@p2.CliStderrOutputStream(2))
}

///|
pub impl @p2.WasiCliEnvironmentAdapter for CliAdapter with get_environment(self) {
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
pub impl @p2.WasiCliEnvironmentAdapter for CliAdapter with get_arguments(self) {
  Ok(self.kernel.args)
}

///|
pub impl @p2.WasiCliEnvironmentAdapter for CliAdapter with initial_cwd(self) {
  Ok(Some(self.kernel.cwd))
}

///|
pub impl @p2.WasiCliExitAdapter for CliAdapter with exit(self, status) {
  match status {
    Ok(_) => self.kernel.exit_code = Some(0)
    Err(_) => self.kernel.exit_code = Some(1)
  }
  Ok(())
}

///|
pub impl @p2.WasiCliExitAdapter for CliAdapter with exit_with_code(self, code) {
  self.kernel.exit_code = Some(code.to_int())
  Ok(())
}

///|
pub impl @p2.WasiCliTerminalStdinAdapter for CliAdapter with get_terminal_stdin(
  _self,
) {
  Ok(None)
}

///|
pub impl @p2.WasiCliTerminalStdoutAdapter for CliAdapter with get_terminal_stdout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p2.WasiCliTerminalStderrAdapter for CliAdapter with get_terminal_stderr(
  _self,
) {
  Ok(None)
}
