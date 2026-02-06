test "xsh script cli ok" {
  let ok = run_file_script(fixture_path_script("script/ok.xsh"), false)
  assert_true(ok.ok)
}

test "xsh script cli failure" {
  let bad = run_file_script(fixture_path_script("script/bad.xsh"), false)
  assert_true(not(bad.ok))
  let msg = match bad.error {
    Some(m) => m
    None => ""
  }
  assert_true(msg.contains("unknown"))
}

fn fixture_path_script(rel : String) -> String {
  let cwd = match @env.current_dir() {
    Some(dir) => dir
    None => "."
  }
  let base = @path.Path(cwd)
  base.join(@path.Path("src/cmd/xsh_test/fixtures/" + rel)).normalize().to_string()
}
