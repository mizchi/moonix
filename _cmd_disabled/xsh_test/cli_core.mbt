///| Shared CLI logic for xsh tests (target-agnostic)

suberror CliError {
  Io(String)
  Parse(String)
  Compile(String)
  Eval(String)
  ImportCycle(String)
} derive(Show, Eq)

struct ImportJob {
  key : String
  abs_path : String
}

struct ImportEdge {
  parent_abs : String
  import_key : String
}

struct ScriptReport {
  ok : Bool
  error : String?
} derive(Show, Eq)

///| Run tests using a custom reader (used by both OS and virtual loaders).
pub fn run_tests_with_reader(
  entry_path : String,
  entry_content : String,
  cycle_debug : Bool,
  read_file : (String) -> String raise CliError
) -> @xsh.TestReport raise CliError {
  let db = @xsh.XshDb::new()
  load_sources_recursive(db, entry_path, entry_content, cycle_debug, read_file)
  let compiled = try {
    @xsh.compile_module(db, entry_path)
  } catch {
    e => raise CliError::Compile(e.to_string())
  }
  let rt = @xsh.Runtime::new(@xsh_capability.CapabilitySet::new())
  for name, target in compiled.aliases {
    rt.set_alias(name, target)
  }
  try {
    rt.run_tests(compiled.ast)
  } catch {
    e => raise CliError::Eval(e.to_string())
  }
}

fn script_success_report() -> ScriptReport {
  { ok: true, error: None }
}

fn script_failure_report(msg : String) -> ScriptReport {
  { ok: false, error: Some(msg) }
}

fn run_script_impl(
  entry_path : String,
  entry_content : String,
  cycle_debug : Bool,
  read_file : (String) -> String raise CliError
) -> Unit raise CliError {
  let db = @xsh.XshDb::new()
  load_sources_recursive(db, entry_path, entry_content, cycle_debug, read_file)
  let compiled = try {
    @xsh.compile_module(db, entry_path)
  } catch {
    e => raise CliError::Compile(e.to_string())
  }
  let rt = @xsh.Runtime::new(@xsh_capability.CapabilitySet::new())
  try {
    let _ = rt.run_compiled(compiled)
    ()
  } catch {
    e => raise CliError::Eval(e.to_string())
  }
}

///| Run a script as a single test case (success if evaluation succeeds).
fn run_script_with_reader(
  entry_path : String,
  entry_content : String,
  cycle_debug : Bool,
  read_file : (String) -> String raise CliError
) -> ScriptReport {
  try {
    run_script_impl(entry_path, entry_content, cycle_debug, read_file)
  } catch {
    e => script_failure_report(e.to_string())
  } noraise {
    _ => script_success_report()
  }
}

///| Run tests with an in-memory fixture map.
pub fn run_virtual_tests(
  entry_path : String,
  files : Map[String, String],
  cycle_debug : Bool
) -> @xsh.TestReport raise CliError {
  let entry_abs = @path.Path(entry_path).normalize().to_string()
  let content = match files.get(entry_abs) {
    Some(c) => c
    None => raise CliError::Io("missing fixture: " + entry_abs)
  }
  let read_file = fn(path : String) -> String raise CliError {
    match files.get(path) {
      Some(c) => c
      None => raise CliError::Io("missing fixture: " + path)
    }
  }
  run_tests_with_reader(entry_path, content, cycle_debug, read_file)
}

fn load_sources_recursive(
  db : @xsh.XshDb,
  entry_path : String,
  entry_content : String,
  cycle_debug : Bool,
  read_file : (String) -> String raise CliError
) -> Unit raise CliError {
  db.set_source(entry_path, entry_content)
  let entry_ast = try {
    @xsh.parse_ast(entry_content)
  } catch {
    e => raise CliError::Parse("parse " + entry_path + ": " + e.to_string())
  }
  let visiting : Map[String, Bool] = {}
  let visited : Map[String, Bool] = {}
  let parent_edge : Map[String, ImportEdge] = {}
  let cache : Map[String, String] = {}
  let entry_abs = @path.Path(entry_path).normalize().to_string()
  cache[entry_abs] = entry_content
  let root = ImportJob::{ key: entry_path, abs_path: entry_abs }
  load_one(db, root, Some(entry_ast), cycle_debug, visiting, visited, parent_edge, cache, read_file)
}

fn load_one(
  db : @xsh.XshDb,
  job : ImportJob,
  ast_hint : @xsh.Module?,
  cycle_debug : Bool,
  visiting : Map[String, Bool],
  visited : Map[String, Bool],
  parent_edge : Map[String, ImportEdge],
  cache : Map[String, String],
  read_file : (String) -> String raise CliError
) -> Unit raise CliError {
  let content = match cache.get(job.abs_path) {
    Some(c) => c
    None => {
      let c = read_file(job.abs_path)
      cache[job.abs_path] = c
      c
    }
  }
  db.set_source(job.key, content)
  if visited.contains(job.abs_path) {
    return
  }
  if visiting.contains(job.abs_path) {
    raise CliError::ImportCycle(build_cycle_message(job.abs_path, job.abs_path, "", cycle_debug, parent_edge))
  }
  visiting[job.abs_path] = true
  let ast = match ast_hint {
    Some(a) => a
    None =>
      try {
        @xsh.parse_ast(content)
      } catch {
        e => raise CliError::Parse("parse " + job.abs_path + ": " + e.to_string())
      }
  }
  for imp in collect_import_paths(ast) {
    let imp_abs = resolve_import_path(job.abs_path, imp)
    if visiting.contains(imp_abs) {
      raise CliError::ImportCycle(build_cycle_message(job.abs_path, imp_abs, imp, cycle_debug, parent_edge))
    }
    let child = ImportJob::{ key: imp, abs_path: imp_abs }
    if not(parent_edge.contains(imp_abs)) {
      parent_edge[imp_abs] = ImportEdge::{ parent_abs: job.abs_path, import_key: imp }
    }
    load_one(db, child, None, cycle_debug, visiting, visited, parent_edge, cache, read_file)
  }
  visiting.remove(job.abs_path)
  visited[job.abs_path] = true
}

fn collect_import_paths(ast : @xsh.Module) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = {}
  for stmt in ast.stmts {
    match stmt {
      @xsh.Stmt::Import(path~) =>
        if not(seen.contains(path)) {
          seen[path] = true
          out.push(path)
        }
      _ => ()
    }
  }
  out
}

fn resolve_import_path(base_path : String, import_path : String) -> String {
  let imp = @path.Path(import_path)
  if imp.is_absolute() {
    imp.to_string()
  } else {
    let base = @path.Path(base_path).dirname()
    base.join(imp).normalize().to_string()
  }
}

fn build_cycle_message(
  current : String,
  target : String,
  import_key_current : String,
  cycle_debug : Bool,
  parent_edge : Map[String, ImportEdge]
) -> String {
  let steps : Array[(String, String, String)] = []
  let mut node = current
  while node != target {
    match parent_edge.get(node) {
      Some(edge) => {
        steps.push((edge.parent_abs, edge.import_key, node))
        node = edge.parent_abs
      }
      None => break
    }
  }
  let buf = StringBuilder::new()
  if node == target {
    let reversed : Array[(String, String, String)] = []
    let len = steps.length()
    for i in 0..<len {
      reversed.push(steps[len - 1 - i])
    }
    let mut first = true
    for step in reversed {
      let (from, imp, to) = step
      if first {
        first = false
      } else {
        buf.write_string(" -> ")
      }
      if cycle_debug {
        write_debug_edge(buf, from, imp, to)
      } else {
        write_simple_edge(buf, from, to)
      }
    }
    if not(reversed.is_empty()) {
      buf.write_string(" -> ")
    }
    if cycle_debug {
      let key = if import_key_current.is_empty() { "<unknown>" } else { import_key_current }
      write_debug_edge(buf, current, key, target)
    } else {
      write_simple_edge(buf, current, target)
    }
  } else {
    if cycle_debug {
      let key = if import_key_current.is_empty() { "<unknown>" } else { import_key_current }
      write_debug_edge(buf, target, key, target)
    } else {
      write_simple_edge(buf, target, target)
    }
  }
  "import cycle: " + buf.to_string()
}

fn write_simple_edge(buf : StringBuilder, from : String, to : String) -> Unit {
  buf.write_string(from)
  buf.write_string(" -> ")
  buf.write_string(to)
}

fn write_debug_edge(buf : StringBuilder, from : String, import_key : String, to : String) -> Unit {
  buf.write_string(from)
  buf.write_string(" --import ")
  buf.write_string(import_key)
  buf.write_string(" (resolved ")
  buf.write_string(to)
  buf.write_string(")--> ")
  buf.write_string(to)
}
