///| Shell command executor

///| Execute a command string
pub fn ShellContext::exec(self : ShellContext, cmd : String) -> Int {
  let parsed = parse_command(cmd)

  match parsed.pipe_to {
    Some(pipe_cmd) => {
      // Execute first command, capture stdout, feed to second command
      let first_result = self.exec_simple(parsed.command, parsed.args)
      if first_result != 0 {
        return first_result
      }
      // Get stdout from first command and use as stdin for pipe
      let pipe_input = self.streams.get_stdout()
      // Reset streams for second command
      self.reset_streams()
      self.pipe_input = Some(pipe_input)
      let result = self.exec(pipe_cmd)
      self.pipe_input = None
      result
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
    _ => {
      try {
        let _ = self.ctx.write(
          @posix.STDERR_FD,
          string_to_bytes("command not found: " + name + "\n"),
        )
      } catch {
        _ => ()
      }
      127
    }
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
  for i = 1; i < parts.length(); i = i + 1 {
    args.push(parts[i])
  }
  ParsedCommand::{ command, args, redirect_out: redirect_file, pipe_to: None }
}

fn split_command(cmd : String) -> Array[String] {
  let parts : Array[String] = []
  let current = StringBuilder::new()
  for c in cmd {
    if c == ' ' || c == '\t' {
      if current.to_string().length() > 0 {
        parts.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
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

