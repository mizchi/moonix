///| Shell built-in commands

fn write_stdout(ctx : @posix.PosixContext, s : String) -> Unit {
  try {
    let _ = ctx.write(@posix.STDOUT_FD, string_to_bytes(s))
  } catch {
    _ => ()
  }
}

fn write_stderr(ctx : @posix.PosixContext, s : String) -> Unit {
  try {
    let _ = ctx.write(@posix.STDERR_FD, string_to_bytes(s))
  } catch {
    _ => ()
  }
}

fn string_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}

fn bytes_to_string(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

///| echo command
pub fn cmd_echo(sh : ShellContext, args : Array[String]) -> Int {
  let buf = StringBuilder::new()
  for i, arg in args {
    if i > 0 {
      buf.write_char(' ')
    }
    buf.write_string(arg)
  }
  buf.write_char('\n')
  write_stdout(sh.ctx, buf.to_string())
  0
}

///| cat command
pub fn cmd_cat(sh : ShellContext, args : Array[String]) -> Int {
  // Read from pipe if available
  match sh.pipe_input {
    Some(data) => {
      write_stdout(sh.ctx, bytes_to_string(data))
      return 0
    }
    None => ()
  }

  if args.is_empty() {
    write_stderr(sh.ctx, "cat: missing file operand\n")
    return 1
  }
  for path in args {
    let abs_path = sh.ctx.resolve_path(path)
    try {
      let content = sh.fs.read_string(abs_path)
      write_stdout(sh.ctx, content)
    } catch {
      _ => {
        write_stderr(sh.ctx, "cat: " + path + ": No such file\n")
        return 1
      }
    }
  }
  0
}

///| ls command
pub fn cmd_ls(sh : ShellContext, args : Array[String]) -> Int {
  let path = if args.is_empty() {
    sh.ctx.getcwd()
  } else {
    sh.ctx.resolve_path(args[0])
  }
  try {
    let entries = sh.fs.readdir(path)
    for entry in entries {
      let suffix = match entry.file_type {
        @fs.FileType::Directory => "/"
        _ => ""
      }
      write_stdout(sh.ctx, entry.name + suffix + "\n")
    }
    0
  } catch {
    _ => {
      write_stderr(sh.ctx, "ls: cannot access '" + path + "'\n")
      1
    }
  }
}

///| pwd command
pub fn cmd_pwd(sh : ShellContext) -> Int {
  write_stdout(sh.ctx, sh.ctx.getcwd() + "\n")
  0
}

///| cd command
pub fn cmd_cd(sh : ShellContext, args : Array[String]) -> Int {
  let path = if args.is_empty() {
    sh.ctx.getenv("HOME").unwrap_or("/")
  } else {
    args[0]
  }
  try {
    sh.ctx.chdir(path)
    0
  } catch {
    _ => {
      write_stderr(sh.ctx, "cd: " + path + ": No such directory\n")
      1
    }
  }
}

///| touch command
pub fn cmd_touch(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "touch: missing file operand\n")
    return 1
  }
  for path in args {
    let abs_path = sh.ctx.resolve_path(path)
    if not(sh.fs.exists(abs_path)) {
      try {
        sh.fs.write_string(abs_path, "")
      } catch {
        _ => {
          write_stderr(sh.ctx, "touch: cannot touch '" + path + "'\n")
          return 1
        }
      }
    }
  }
  0
}

///| mkdir command
pub fn cmd_mkdir(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "mkdir: missing operand\n")
    return 1
  }
  let use_p = args.length() > 0 && args[0] == "-p"
  let start = if use_p { 1 } else { 0 }
  for i = start; i < args.length(); i = i + 1 {
    let path = args[i]
    let abs_path = sh.ctx.resolve_path(path)
    try {
      if use_p {
        sh.fs.mkdir_p(abs_path)
      } else {
        sh.fs.mkdir(abs_path)
      }
    } catch {
      _ => {
        write_stderr(sh.ctx, "mkdir: cannot create directory '" + path + "'\n")
        return 1
      }
    }
  }
  0
}

///| rm command
pub fn cmd_rm(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "rm: missing operand\n")
    return 1
  }
  let recursive = args.length() > 0 && (args[0] == "-r" || args[0] == "-rf")
  let start = if recursive { 1 } else { 0 }
  for i = start; i < args.length(); i = i + 1 {
    let path = args[i]
    let abs_path = sh.ctx.resolve_path(path)
    try {
      if recursive {
        sh.fs.rm_rf(abs_path)
      } else {
        sh.fs.remove(abs_path)
      }
    } catch {
      _ => {
        write_stderr(sh.ctx, "rm: cannot remove '" + path + "'\n")
        return 1
      }
    }
  }
  0
}

///| cp command
pub fn cmd_cp(sh : ShellContext, args : Array[String]) -> Int {
  if args.length() < 2 {
    write_stderr(sh.ctx, "cp: missing destination\n")
    return 1
  }
  let src = sh.ctx.resolve_path(args[0])
  let dst = sh.ctx.resolve_path(args[1])
  try {
    sh.fs.copy_file(src, dst)
    0
  } catch {
    _ => {
      write_stderr(sh.ctx, "cp: cannot copy '" + args[0] + "'\n")
      1
    }
  }
}

///| mv command
pub fn cmd_mv(sh : ShellContext, args : Array[String]) -> Int {
  if args.length() < 2 {
    write_stderr(sh.ctx, "mv: missing destination\n")
    return 1
  }
  let src = sh.ctx.resolve_path(args[0])
  let dst = sh.ctx.resolve_path(args[1])
  try {
    sh.fs.rename(src, dst)
    0
  } catch {
    _ => {
      write_stderr(sh.ctx, "mv: cannot move '" + args[0] + "'\n")
      1
    }
  }
}

///| env command
pub fn cmd_env(sh : ShellContext) -> Int {
  let env_vars = sh.ctx.get_all_env()
  for kv in env_vars {
    write_stdout(sh.ctx, kv.0 + "=" + kv.1 + "\n")
  }
  0
}

///| export command
pub fn cmd_export(sh : ShellContext, args : Array[String]) -> Int {
  for arg in args {
    let eq_pos = find_char_pos(arg, '=')
    match eq_pos {
      Some(pos) => {
        let key = substring(arg, 0, pos)
        let value = substring(arg, pos + 1, arg.length())
        sh.ctx.setenv(key, value)
      }
      None => {
        write_stderr(sh.ctx, "export: invalid format, use KEY=VALUE\n")
        return 1
      }
    }
  }
  0
}

///| write command (write <file> <content...>)
pub fn cmd_write(sh : ShellContext, args : Array[String]) -> Int {
  if args.length() < 2 {
    write_stderr(sh.ctx, "write: usage: write <file> <content>\n")
    return 1
  }
  let path = sh.ctx.resolve_path(args[0])
  let content = StringBuilder::new()
  for i in 1..<args.length() {
    if i > 1 {
      content.write_char(' ')
    }
    content.write_string(args[i])
  }
  content.write_char('\n')
  try {
    sh.fs.write_string(path, content.to_string())
    0
  } catch {
    _ => {
      write_stderr(sh.ctx, "write: cannot write to '" + args[0] + "'\n")
      1
    }
  }
}

///| head command
pub fn cmd_head(sh : ShellContext, args : Array[String]) -> Int {
  let n = 10
  let input = match sh.pipe_input {
    Some(data) => bytes_to_string(data)
    None => {
      if args.is_empty() {
        write_stderr(sh.ctx, "head: missing file operand\n")
        return 1
      }
      let path = sh.ctx.resolve_path(args[0])
      try {
        sh.fs.read_string(path)
      } catch {
        _ => {
          write_stderr(sh.ctx, "head: cannot read '" + args[0] + "'\n")
          return 1
        }
      }
    }
  }
  let lines = split_lines(input)
  let count = if lines.length() < n { lines.length() } else { n }
  for i in 0..<count {
    write_stdout(sh.ctx, lines[i] + "\n")
  }
  0
}

///| tail command
pub fn cmd_tail(sh : ShellContext, args : Array[String]) -> Int {
  let n = 10
  let input = match sh.pipe_input {
    Some(data) => bytes_to_string(data)
    None => {
      if args.is_empty() {
        write_stderr(sh.ctx, "tail: missing file operand\n")
        return 1
      }
      let path = sh.ctx.resolve_path(args[0])
      try {
        sh.fs.read_string(path)
      } catch {
        _ => {
          write_stderr(sh.ctx, "tail: cannot read '" + args[0] + "'\n")
          return 1
        }
      }
    }
  }
  let lines = split_lines(input)
  let start = if lines.length() > n { lines.length() - n } else { 0 }
  for i = start; i < lines.length(); i = i + 1 {
    write_stdout(sh.ctx, lines[i] + "\n")
  }
  0
}

///| grep command
pub fn cmd_grep(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "grep: missing pattern\n")
    return 1
  }
  let pattern = args[0]
  let input = match sh.pipe_input {
    Some(data) => bytes_to_string(data)
    None => {
      if args.length() < 2 {
        write_stderr(sh.ctx, "grep: missing file operand\n")
        return 1
      }
      let path = sh.ctx.resolve_path(args[1])
      try {
        sh.fs.read_string(path)
      } catch {
        _ => {
          write_stderr(sh.ctx, "grep: cannot read '" + args[1] + "'\n")
          return 1
        }
      }
    }
  }
  let lines = split_lines(input)
  let mut found = false
  for line in lines {
    if contains(line, pattern) {
      write_stdout(sh.ctx, line + "\n")
      found = true
    }
  }
  if found { 0 } else { 1 }
}

// Helper functions

fn find_char_pos(s : String, c : Char) -> Int? {
  let target = c.to_int()
  for i, ch in s {
    if ch.to_int() == target {
      return Some(i)
    }
  }
  None
}

fn substring(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let mut idx = 0
  for ch in s {
    if idx >= start && idx < end {
      buf.write_char(ch)
    }
    idx += 1
  }
  buf.to_string()
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
  if current.to_string().length() > 0 {
    lines.push(current.to_string())
  }
  lines
}

fn contains(haystack : String, needle : String) -> Bool {
  if needle.length() > haystack.length() {
    return false
  }
  let hay_chars : Array[Char] = []
  for ch in haystack {
    hay_chars.push(ch)
  }
  let need_chars : Array[Char] = []
  for ch in needle {
    need_chars.push(ch)
  }
  let limit = hay_chars.length() - need_chars.length()
  for i in 0..<=limit {
    let mut matched = true
    for j in 0..<need_chars.length() {
      if hay_chars[i + j] != need_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}

///| true command - always returns 0
pub fn cmd_true(_sh : ShellContext, _args : Array[String]) -> Int {
  0
}

///| false command - always returns 1
pub fn cmd_false(_sh : ShellContext, _args : Array[String]) -> Int {
  1
}

///| exit command - returns exit code (default 0)
pub fn cmd_exit(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    sh.last_exit_code
  } else {
    match parse_int(args[0]) {
      Some(code) => code
      None => {
        write_stderr(sh.ctx, "exit: numeric argument required\n")
        2
      }
    }
  }
}

///| sleep command - in virtual env, returns immediately
pub fn cmd_sleep(_sh : ShellContext, _args : Array[String]) -> Int {
  // In virtual environment, sleep is a no-op
  // Real implementation would need async support
  0
}

///| Glob pattern matching
pub fn glob_match(pattern : String, text : String) -> Bool {
  let p_chars : Array[Char] = []
  let t_chars : Array[Char] = []
  for c in pattern {
    p_chars.push(c)
  }
  for c in text {
    t_chars.push(c)
  }
  glob_match_chars(p_chars, 0, t_chars, 0)
}

fn glob_match_chars(
  pattern : Array[Char],
  pi : Int,
  text : Array[Char],
  ti : Int
) -> Bool {
  let plen = pattern.length()
  let tlen = text.length()

  if pi >= plen {
    return ti >= tlen
  }

  let p = pattern[pi]

  match p {
    '*' => {
      // Try matching zero or more characters
      // First, try matching zero chars (skip the *)
      if glob_match_chars(pattern, pi + 1, text, ti) {
        return true
      }
      // Then try matching one char and recurse
      if ti < tlen && glob_match_chars(pattern, pi, text, ti + 1) {
        return true
      }
      false
    }
    '?' => {
      // Match any single character
      if ti < tlen {
        glob_match_chars(pattern, pi + 1, text, ti + 1)
      } else {
        false
      }
    }
    '[' => {
      // Character class [abc] or [a-z]
      if ti >= tlen {
        return false
      }
      let t = text[ti]
      let mut matched = false
      let mut negated = false
      let mut i = pi + 1

      if i < plen && pattern[i] == '!' {
        negated = true
        i += 1
      }

      while i < plen && pattern[i] != ']' {
        if i + 2 < plen && pattern[i + 1] == '-' && pattern[i + 2] != ']' {
          // Range a-z
          let lo = pattern[i]
          let hi = pattern[i + 2]
          if t >= lo && t <= hi {
            matched = true
          }
          i += 3
        } else {
          if pattern[i] == t {
            matched = true
          }
          i += 1
        }
      }

      if negated {
        matched = not(matched)
      }

      if matched && i < plen && pattern[i] == ']' {
        glob_match_chars(pattern, i + 1, text, ti + 1)
      } else {
        false
      }
    }
    _ => {
      // Literal character
      if ti < tlen && text[ti] == p {
        glob_match_chars(pattern, pi + 1, text, ti + 1)
      } else {
        false
      }
    }
  }
}

///| Expand glob pattern to matching files
pub fn expand_glob(
  fs : &@fs.FileSystemBackend,
  cwd : String,
  pattern : String
) -> Array[String] {
  let results : Array[String] = []

  // Determine directory to search
  let (dir, file_pattern) = if pattern.contains("/") {
    let last_slash = find_last_char(pattern, '/')
    match last_slash {
      Some(pos) =>
        if pos == 0 {
          ("/", substring(pattern, 1, pattern.length()))
        } else {
          (substring(pattern, 0, pos), substring(pattern, pos + 1, pattern.length()))
        }
      None => (cwd, pattern)
    }
  } else {
    (cwd, pattern)
  }

  // Check if pattern has glob chars
  if not(has_glob_chars(file_pattern)) {
    results.push(pattern)
    return results
  }

  // List directory and match
  try {
    let entries = fs.readdir(dir)
    for entry in entries {
      if glob_match(file_pattern, entry.name) {
        let path = if dir == "/" {
          "/" + entry.name
        } else {
          dir + "/" + entry.name
        }
        results.push(path)
      }
    }
  } catch {
    _ => ()
  }

  // If no matches, return original pattern
  if results.is_empty() {
    results.push(pattern)
  }

  results
}

fn has_glob_chars(s : String) -> Bool {
  for c in s {
    if c == '*' || c == '?' || c == '[' {
      return true
    }
  }
  false
}

fn find_last_char(s : String, target : Char) -> Int? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    if chars[i] == target {
      return Some(i)
    }
  }
  None
}

///| Parse integer from string
fn parse_int(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let mut result = 0
  let mut negative = false
  let mut start = 0
  if s[0] == '-' {
    negative = true
    start = 1
  } else if s[0] == '+' {
    start = 1
  }
  for i in start..<s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(if negative { -result } else { result })
}

///| test command - evaluate conditional expressions
pub fn cmd_test(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    return 1 // empty test is false
  }
  if test_expr(sh, args) { 0 } else { 1 }
}

///| [ command - alias for test, requires ] at end
pub fn cmd_bracket(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "[: missing ]\n")
    return 2
  }
  let last = args[args.length() - 1]
  if last != "]" {
    write_stderr(sh.ctx, "[: missing ]\n")
    return 2
  }
  // Remove trailing ]
  let test_args : Array[String] = []
  for i in 0..<(args.length() - 1) {
    test_args.push(args[i])
  }
  cmd_test(sh, test_args)
}

///| Evaluate test expression
fn test_expr(sh : ShellContext, args : Array[String]) -> Bool {
  let len = args.length()
  if len == 0 {
    return false
  }
  // Unary: ! expr
  if args[0] == "!" {
    let rest : Array[String] = []
    for i in 1..<len {
      rest.push(args[i])
    }
    return not(test_expr(sh, rest))
  }
  // Unary file tests: -e, -f, -d, -z, -n
  if len == 2 {
    let op = args[0]
    let arg = args[1]
    match op {
      "-e" => return sh.fs.exists(sh.ctx.resolve_path(arg))
      "-f" => return sh.fs.is_file(sh.ctx.resolve_path(arg))
      "-d" => return sh.fs.is_dir(sh.ctx.resolve_path(arg))
      "-z" => return arg.is_empty()
      "-n" => return not(arg.is_empty())
      "-r" | "-w" | "-x" => return sh.fs.exists(sh.ctx.resolve_path(arg)) // simplified
      _ => ()
    }
  }
  // Single argument: true if non-empty
  if len == 1 {
    return not(args[0].is_empty())
  }
  // Binary: arg1 op arg2
  if len == 3 {
    let left = args[0]
    let op = args[1]
    let right = args[2]
    match op {
      // String comparison
      "=" | "==" => return left == right
      "!=" => return left != right
      // Numeric comparison
      "-eq" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l == r
          _ => return false
        }
      "-ne" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l != r
          _ => return false
        }
      "-lt" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l < r
          _ => return false
        }
      "-le" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l <= r
          _ => return false
        }
      "-gt" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l > r
          _ => return false
        }
      "-ge" =>
        match (parse_int(left), parse_int(right)) {
          (Some(l), Some(r)) => return l >= r
          _ => return false
        }
      _ => ()
    }
  }
  // Default: false for unknown expressions
  false
}
