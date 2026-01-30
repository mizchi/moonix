///| Shell command executor

///| Execute a command string
pub fn ShellContext::exec(self : ShellContext, cmd : String) -> Int {
  let parsed = parse_command(cmd)

  let result = match parsed.pipe_to {
    Some(pipe_cmd) => {
      // Execute first command, capture stdout, feed to second command
      let first_result = self.exec_simple(parsed.command, parsed.args)
      if first_result != 0 {
        first_result
      } else {
        // Get stdout from first command and use as stdin for pipe
        let pipe_input = self.streams.get_stdout()
        // Reset streams for second command
        self.reset_streams()
        self.pipe_input = Some(pipe_input)
        let result = self.exec(pipe_cmd)
        self.pipe_input = None
        result
      }
    }
    None => {
      let result = self.exec_simple(parsed.command, parsed.args)
      // Handle output redirect
      match parsed.redirect_out {
        Some(file) => {
          let stdout = self.streams.get_stdout()
          let path = self.ctx.resolve_path(file)
          try {
            self.fs.write_file(path, stdout)
            // Clear stdout since it was redirected
            self.reset_streams()
          } catch {
            _ => {
              try {
                let _ = self.ctx.write(
                  @posix.STDERR_FD,
                  string_to_bytes("cannot write to: " + file + "\n"),
                )
              } catch {
                _ => ()
              }
            }
          }
        }
        None => ()
      }
      result
    }
  }
  self.last_exit_code = result
  result
}

///| Execute a simple command (no pipes/redirects)
pub fn ShellContext::exec_simple(
  self : ShellContext,
  name : String,
  args : Array[String]
) -> Int {
  if name.is_empty() {
    return 0
  }
  match name {
    "echo" => cmd_echo(self, args)
    "cat" => cmd_cat(self, args)
    "ls" => cmd_ls(self, args)
    "pwd" => cmd_pwd(self)
    "cd" => cmd_cd(self, args)
    "touch" => cmd_touch(self, args)
    "mkdir" => cmd_mkdir(self, args)
    "rm" => cmd_rm(self, args)
    "cp" => cmd_cp(self, args)
    "mv" => cmd_mv(self, args)
    "env" => cmd_env(self)
    "export" => cmd_export(self, args)
    "write" => cmd_write(self, args)
    "head" => cmd_head(self, args)
    "tail" => cmd_tail(self, args)
    "grep" => cmd_grep(self, args)
    "true" => cmd_true(self, args)
    "false" => cmd_false(self, args)
    "exit" => cmd_exit(self, args)
    "sleep" => cmd_sleep(self, args)
    "test" => cmd_test(self, args)
    "[" => cmd_bracket(self, args)
    _ => self.exec_external(name, args)
  }
}

///| Try to execute an external WASM command
fn ShellContext::exec_external(
  self : ShellContext,
  name : String,
  args : Array[String]
) -> Int {
  // Check if wasm_runner is available
  let runner = match self.wasm_runner {
    Some(r) => r
    None => {
      write_stderr_msg(self, "command not found: " + name + "\n")
      return 127
    }
  }

  // Look for /bin/{name}.wasm
  let wasm_path = "/bin/" + name + ".wasm"
  let wasm_bytes = try {
    self.fs.read_file(wasm_path)
  } catch {
    _ => {
      write_stderr_msg(self, "command not found: " + name + "\n")
      return 127
    }
  }

  // Prepare stdin from pipe_input
  let stdin = match self.pipe_input {
    Some(data) => data
    None => Bytes::new(0)
  }

  // Get environment variables
  let env = self.ctx.get_all_env()
  let cwd = self.ctx.getcwd()

  // Execute WASM
  let WasmRunnerFn(run_fn) = runner
  match run_fn(wasm_bytes, stdin, args, env, cwd) {
    Ok((exit_code, stdout, stderr)) => {
      // Write outputs to streams
      if stdout.length() > 0 {
        try {
          let _ = self.ctx.write(@posix.STDOUT_FD, stdout)
        } catch {
          _ => ()
        }
      }
      if stderr.length() > 0 {
        try {
          let _ = self.ctx.write(@posix.STDERR_FD, stderr)
        } catch {
          _ => ()
        }
      }
      exit_code
    }
    Err(msg) => {
      write_stderr_msg(self, "wasm error: " + msg + "\n")
      1
    }
  }
}

fn write_stderr_msg(sh : ShellContext, msg : String) -> Unit {
  try {
    let _ = sh.ctx.write(@posix.STDERR_FD, string_to_bytes(msg))
  } catch {
    _ => ()
  }
}

///| Parse command string into structured form
pub fn parse_command(cmd : String) -> ParsedCommand {
  // Find pipe first (lower precedence)
  let pipe_pos = find_char_pos(cmd, '|')
  match pipe_pos {
    Some(pos) => {
      let left = trim_str(substring(cmd, 0, pos))
      let right = trim_str(substring(cmd, pos + 1, cmd.length()))
      let left_parsed = parse_simple_command(left)
      ParsedCommand::{
        command: left_parsed.command,
        args: left_parsed.args,
        redirect_out: left_parsed.redirect_out,
        pipe_to: Some(right),
      }
    }
    None => parse_simple_command(cmd)
  }
}

fn parse_simple_command(cmd : String) -> ParsedCommand {
  // Find redirect >
  let redirect_pos = find_char_pos(cmd, '>')
  let (main_cmd, redirect_file) : (String, String?) = match redirect_pos {
    Some(pos) => {
      let left = trim_str(substring(cmd, 0, pos))
      let right = trim_str(substring(cmd, pos + 1, cmd.length()))
      (left, Some(right))
    }
    None => (cmd, None)
  }

  let parts = split_command(main_cmd)
  let command = if parts.is_empty() { "" } else { parts[0] }
  let args : Array[String] = []
  for i in 1..<parts.length() {
    args.push(parts[i])
  }
  ParsedCommand::{ command, args, redirect_out: redirect_file, pipe_to: None }
}

fn split_command(cmd : String) -> Array[String] {
  let parts : Array[String] = []
  let current = StringBuilder::new()
  let chars : Array[Char] = []
  for c in cmd {
    chars.push(c)
  }
  let len = chars.length()
  let mut i = 0

  while i < len {
    let c = chars[i]

    if c == ' ' || c == '\t' {
      // Whitespace: end current token
      if current.to_string().length() > 0 {
        parts.push(current.to_string())
        current.reset()
      }
      i += 1
    } else if c == '\'' {
      // Single quote: read until closing quote, no escapes
      i += 1
      while i < len && chars[i] != '\'' {
        current.write_char(chars[i])
        i += 1
      }
      if i < len {
        i += 1 // skip closing quote
      }
    } else if c == '"' {
      // Double quote: read until closing quote, handle escapes
      i += 1
      while i < len && chars[i] != '"' {
        if chars[i] == '\\' && i + 1 < len {
          i += 1
          current.write_char(chars[i])
        } else {
          current.write_char(chars[i])
        }
        i += 1
      }
      if i < len {
        i += 1 // skip closing quote
      }
    } else if c == '\\' && i + 1 < len {
      // Escape: next char is literal
      i += 1
      current.write_char(chars[i])
      i += 1
    } else {
      // Regular character
      current.write_char(c)
      i += 1
    }
  }

  if current.to_string().length() > 0 {
    parts.push(current.to_string())
  }
  parts
}

fn trim_str(s : String) -> String {
  let chars : Array[Char] = []
  for ch in s {
    chars.push(ch)
  }
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start += 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end -= 1
  }
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

