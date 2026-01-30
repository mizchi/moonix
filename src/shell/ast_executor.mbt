///| AST-based command executor
///| Executes parsed shell commands from the sh package

///| Execute a parsed Command AST
pub fn ShellContext::exec_command(self : ShellContext, cmd : @sh.Command) -> Int {
  match cmd {
    @sh.Simple(simple) => self.exec_simple_command(simple)
    @sh.List(list) => self.exec_command_list(list)
    @sh.IfCmd(if_clause) => self.exec_if(if_clause)
    @sh.WhileCmd(while_clause) => self.exec_while(while_clause)
    @sh.ForCmd(for_clause) => self.exec_for(for_clause)
    @sh.Subshell(list) => self.exec_command_list(list) // simplified
    @sh.BraceGroup(list) => self.exec_command_list(list)
    @sh.Pipeline(_) | @sh.CaseCmd(_) | @sh.FuncDef(_) => {
      // Not yet implemented
      0
    }
  }
}

///| Execute a SimpleCommand
fn ShellContext::exec_simple_command(self : ShellContext, cmd : @sh.SimpleCommand) -> Int {
  // Handle variable assignments
  for assign in cmd.assigns {
    let (name, word) = assign
    let value = self.expand_word(word)
    self.ctx.setenv(name, value)
  }

  // If no words, just assignments
  if cmd.words.is_empty() {
    return 0
  }

  // Expand words with glob
  let expanded : Array[String] = []
  for word in cmd.words {
    let s = self.expand_word(word)
    // Check for glob patterns and expand
    if has_glob_chars(s) {
      let matches = expand_glob(self.fs, self.ctx.getcwd(), s)
      for m in matches {
        expanded.push(m)
      }
    } else {
      expanded.push(s)
    }
  }

  let name = expanded[0]
  let args : Array[String] = []
  for i in 1..<expanded.length() {
    args.push(expanded[i])
  }

  self.exec_simple(name, args)
}

///| Execute a CommandList (with && || ;)
fn ShellContext::exec_command_list(self : ShellContext, list : @sh.CommandList) -> Int {
  // Execute first pipeline
  let mut result = self.exec_pipeline(list.first)

  // Execute rest with operators
  for item in list.rest {
    let (op, pipeline) = item
    match op {
      @sh.Seq => result = self.exec_pipeline(pipeline)
      @sh.And =>
        if result == 0 {
          result = self.exec_pipeline(pipeline)
        }
      @sh.Or =>
        if result != 0 {
          result = self.exec_pipeline(pipeline)
        }
      @sh.Background => {
        // Background not supported in virtual env, run sync
        result = self.exec_pipeline(pipeline)
      }
    }
  }
  result
}

///| Execute a Pipeline
fn ShellContext::exec_pipeline(self : ShellContext, pipeline : @sh.Pipeline) -> Int {
  if pipeline.commands.is_empty() {
    return 0
  }

  // For single command, execute directly
  if pipeline.commands.length() == 1 {
    let result = self.exec_command(pipeline.commands[0])
    return if pipeline.bang { if result == 0 { 1 } else { 0 } } else { result }
  }

  // Multi-command pipeline
  let mut result = 0
  let mut pipe_data : Bytes? = None

  for i in 0..<pipeline.commands.length() {
    // Set pipe input from previous command
    match pipe_data {
      Some(data) => {
        self.reset_streams()
        self.pipe_input = Some(data)
      }
      None => ()
    }

    result = self.exec_command(pipeline.commands[i])

    // Capture output for next command
    if i < pipeline.commands.length() - 1 {
      pipe_data = Some(self.streams.get_stdout())
    }

    self.pipe_input = None
  }

  if pipeline.bang { if result == 0 { 1 } else { 0 } } else { result }
}

///| Execute if statement
fn ShellContext::exec_if(self : ShellContext, if_clause : @sh.IfClause) -> Int {
  // Evaluate condition
  let cond_result = self.exec_command_list(if_clause.condition)

  if cond_result == 0 {
    // Condition true, execute then body
    return self.exec_command_list(if_clause.then_body)
  }

  // Check elif parts
  for elif in if_clause.elif_parts {
    let (elif_cond, elif_body) = elif
    let elif_result = self.exec_command_list(elif_cond)
    if elif_result == 0 {
      return self.exec_command_list(elif_body)
    }
  }

  // Execute else body if present
  match if_clause.else_body {
    Some(else_body) => self.exec_command_list(else_body)
    None => 0
  }
}

///| Execute while/until loop
fn ShellContext::exec_while(self : ShellContext, while_clause : @sh.WhileClause) -> Int {
  let mut result = 0
  let max_iterations = 10000 // Safety limit
  let mut iterations = 0

  while iterations < max_iterations {
    let cond_result = self.exec_command_list(while_clause.condition)
    let should_continue = if while_clause.is_until {
      cond_result != 0 // until: continue while condition is false
    } else {
      cond_result == 0 // while: continue while condition is true
    }

    if not(should_continue) {
      break
    }

    result = self.exec_command_list(while_clause.body)
    iterations += 1
  }
  result
}

///| Execute for loop
fn ShellContext::exec_for(self : ShellContext, for_clause : @sh.ForClause) -> Int {
  let words = match for_clause.words {
    Some(w) => w
    None => [] // "$@" not implemented
  }

  let mut result = 0
  for word in words {
    let value = self.expand_word(word)
    self.ctx.setenv(for_clause.varname, value)
    result = self.exec_command_list(for_clause.body)
  }
  result
}

///| Expand a Word to string
fn ShellContext::expand_word(self : ShellContext, word : @sh.Word) -> String {
  let buf = StringBuilder::new()
  for part in word.parts {
    match part {
      @sh.Literal(s) => {
        // Check for unexpanded $(cmd) or $((expr)) patterns
        let expanded = self.expand_literal(s)
        buf.write_string(expanded)
      }
      @sh.SingleQuoted(s) => buf.write_string(s)
      @sh.Variable(name) =>
        match self.ctx.getenv(name) {
          Some(val) => buf.write_string(val)
          None => ()
        }
      @sh.SpecialVar(c) =>
        match c {
          '?' => buf.write_string(self.last_exit_code.to_string())
          '0' => buf.write_string("sh")
          '#' => buf.write_string("0") // no positional params
          '$' => buf.write_string("1") // fake PID
          _ => ()
        }
      @sh.DoubleQuoted(parts) => {
        let inner = @sh.Word::new(parts)
        buf.write_string(self.expand_word(inner))
      }
      @sh.ArithSub(expr) => {
        // Simple arithmetic evaluation
        match eval_arith(expr) {
          Some(n) => buf.write_string(n.to_string())
          None => ()
        }
      }
      @sh.CommandSub(cmd) => {
        // Execute command and capture output
        self.reset_streams()
        let _ = self.exec_command(cmd)
        let output = self.streams.get_stdout()
        // Convert to string and trim trailing newline
        let s = bytes_to_str(output)
        buf.write_string(trim_trailing_newline(s))
      }
      @sh.Glob(pattern) => {
        // Glob in word context - just use pattern literally
        buf.write_string(pattern)
      }
    }
  }
  buf.to_string()
}

///| Execute shell script using parser
pub fn ShellContext::exec_script(self : ShellContext, script : String) -> Int {
  try {
    let cmd = @sh.parse(script)
    let result = self.exec_command(cmd)
    self.last_exit_code = result
    result
  } catch {
    _ => {
      write_stderr_msg(self, "syntax error\n")
      self.last_exit_code = 2
      2
    }
  }
}

///| Convert Bytes to String
fn bytes_to_str(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

///| Trim trailing newlines
fn trim_trailing_newline(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == '\n' || chars[end - 1] == '\r') {
    end -= 1
  }
  let buf = StringBuilder::new()
  for i in 0..<end {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///| Simple arithmetic evaluation
fn eval_arith(expr : String) -> Int? {
  // Very simple: just parse as integer or handle basic +/-
  let trimmed = trim_spaces(expr)

  // Try direct integer parse first
  match parse_int(trimmed) {
    Some(n) => return Some(n)
    None => ()
  }

  // Try simple addition/subtraction
  let chars : Array[Char] = []
  for c in trimmed {
    chars.push(c)
  }

  // Find + or - (not at start)
  for i in 1..<chars.length() {
    if chars[i] == '+' {
      let left = substring_chars(chars, 0, i)
      let right = substring_chars(chars, i + 1, chars.length())
      match (parse_int(left), parse_int(right)) {
        (Some(l), Some(r)) => return Some(l + r)
        _ => ()
      }
    } else if chars[i] == '-' {
      let left = substring_chars(chars, 0, i)
      let right = substring_chars(chars, i + 1, chars.length())
      match (parse_int(left), parse_int(right)) {
        (Some(l), Some(r)) => return Some(l - r)
        _ => ()
      }
    } else if chars[i] == '*' {
      let left = substring_chars(chars, 0, i)
      let right = substring_chars(chars, i + 1, chars.length())
      match (parse_int(left), parse_int(right)) {
        (Some(l), Some(r)) => return Some(l * r)
        _ => ()
      }
    } else if chars[i] == '/' {
      let left = substring_chars(chars, 0, i)
      let right = substring_chars(chars, i + 1, chars.length())
      match (parse_int(left), parse_int(right)) {
        (Some(l), Some(r)) if r != 0 => return Some(l / r)
        _ => ()
      }
    }
  }

  None
}

fn substring_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i in start..<end {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///| Expand literal string that may contain $(cmd) or $((expr))
pub fn ShellContext::expand_literal(self : ShellContext, s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }

  let buf = StringBuilder::new()
  let mut i = 0

  while i < chars.length() {
    if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '(' {
      if i + 2 < chars.length() && chars[i + 2] == '(' {
        // $((expr)) - arithmetic expansion
        i += 3
        let expr_start = i
        let mut depth = 1
        while i < chars.length() && depth > 0 {
          if i + 1 < chars.length() && chars[i] == ')' && chars[i + 1] == ')' {
            depth -= 1
            if depth == 0 {
              break
            }
          }
          i += 1
        }
        let expr = substring_chars(chars, expr_start, i)
        match eval_arith(expr) {
          Some(n) => buf.write_string(n.to_string())
          None => ()
        }
        i += 2 // skip ))
      } else {
        // $(cmd) - command substitution
        i += 2
        let cmd_start = i
        let mut depth = 1
        while i < chars.length() && depth > 0 {
          if chars[i] == '(' {
            depth += 1
          } else if chars[i] == ')' {
            depth -= 1
          }
          if depth > 0 {
            i += 1
          }
        }
        let cmd_str = substring_chars(chars, cmd_start, i)
        i += 1 // skip )

        // Execute command and capture output
        self.reset_streams()
        let _ = self.exec_script(cmd_str)
        let output = self.streams.get_stdout()
        let output_str = bytes_to_str(output)
        buf.write_string(trim_trailing_newline(output_str))
      }
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }

  buf.to_string()
}

fn trim_spaces(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let mut start = 0
  let mut end = chars.length()
  while start < end && chars[start] == ' ' {
    start += 1
  }
  while end > start && chars[end - 1] == ' ' {
    end -= 1
  }
  let buf = StringBuilder::new()
  for i in start..<end {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
