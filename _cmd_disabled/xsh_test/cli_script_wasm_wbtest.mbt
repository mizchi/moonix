test "xsh script cli wasm ok" {
  let files : Map[String, String] = {}
  files["/fixtures/ok.xsh"] = "let x = 1\nx"
  let ok = run_virtual_script("/fixtures/ok.xsh", files, false)
  assert_true(ok.ok)
}

test "xsh script cli wasm failure" {
  let files : Map[String, String] = {}
  files["/fixtures/bad.xsh"] = "unknown"
  let bad = run_virtual_script("/fixtures/bad.xsh", files, false)
  assert_true(not(bad.ok))
  let msg = match bad.error {
    Some(m) => m
    None => ""
  }
  assert_true(msg.contains("unknown"))
}

fn run_virtual_script(
  entry_path : String,
  files : Map[String, String],
  cycle_debug : Bool
) -> ScriptReport {
  let entry_abs = @path.Path(entry_path).normalize().to_string()
  let content = match files.get(entry_abs) {
    Some(c) => c
    None => return script_failure_report("Io(missing fixture: " + entry_abs + ")")
  }
  let read_file = fn(path : String) -> String raise CliError {
    match files.get(path) {
      Some(c) => c
      None => raise CliError::Io("missing fixture: " + path)
    }
  }
  run_script_with_reader(entry_path, content, cycle_debug, read_file)
}
