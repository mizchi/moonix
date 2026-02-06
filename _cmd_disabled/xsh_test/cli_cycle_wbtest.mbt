///| CLI integration test for import cycle errors

test "xsh test cli import cycle" {
  let path = fixture_path_cycle("cycle/a.xsh")
  let result : Result[@xsh.TestReport, CliError] = try? run_file_tests(path, true)
  match result {
    Ok(_) => fail("expected import cycle error")
    Err(CliError::ImportCycle(msg)) => {
      assert_true(msg.contains("import cycle"))
      assert_true(msg.contains("a.xsh"))
      assert_true(msg.contains("b.xsh"))
      assert_true(msg.contains("c.xsh"))
      assert_true(msg.contains("--import"))
      assert_true(msg.contains("resolved"))
    }
    Err(e) => fail("unexpected error: " + e.to_string())
  }
}

fn fixture_path_cycle(rel : String) -> String {
  let cwd = match @env.current_dir() {
    Some(dir) => dir
    None => "."
  }
  let base = @path.Path(cwd)
  base.join(@path.Path("src/cmd/xsh_test/fixtures/" + rel)).normalize().to_string()
}
