///| WASM-friendly CLI import cycle test using in-memory fixtures

test "xsh test cli import cycle wasm" {
  let files : Map[String, String] = {}
  files["/fixtures/a.xsh"] = "import \"b.xsh\"\n"
  files["/fixtures/b.xsh"] = "import \"c.xsh\"\n"
  files["/fixtures/c.xsh"] = "import \"a.xsh\"\n"
  let result : Result[@xsh.TestReport, CliError] = try? run_virtual_tests("/fixtures/a.xsh", files, true)
  match result {
    Ok(_) => fail("expected import cycle error")
    Err(CliError::ImportCycle(msg)) => {
      assert_true(msg.contains("import cycle"))
      assert_true(msg.contains("/fixtures/a.xsh"))
      assert_true(msg.contains("/fixtures/b.xsh"))
      assert_true(msg.contains("/fixtures/c.xsh"))
      assert_true(msg.contains("--import"))
      assert_true(msg.contains("resolved"))
    }
    Err(e) => fail("unexpected error: " + e.to_string())
  }
}
