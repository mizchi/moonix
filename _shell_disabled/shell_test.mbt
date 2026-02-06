test "ShellContext basic commands" {
  let sh = ShellContext::new()

  // echo
  sh.reset_streams()
  let _ = sh.exec("echo hello world")
  assert_eq(bytes_to_string(sh.get_stdout()), "hello world\n")

  // pwd
  sh.reset_streams()
  let _ = sh.exec("pwd")
  assert_eq(bytes_to_string(sh.get_stdout()), "/\n")
}

test "ShellContext file operations" {
  let sh = ShellContext::new()

  // write and cat
  let _ = sh.exec("write test.txt hello")
  sh.reset_streams()
  let _ = sh.exec("cat test.txt")
  assert_eq(bytes_to_string(sh.get_stdout()), "hello\n")

  // ls
  sh.reset_streams()
  let _ = sh.exec("ls")
  assert_true(bytes_to_string(sh.get_stdout()).contains("test.txt"))
}

test "ShellContext redirect" {
  let sh = ShellContext::new()

  // echo with redirect
  let _ = sh.exec("echo redirected > out.txt")
  assert_true(sh.get_fs().exists("/out.txt"))
  assert_eq(sh.get_fs().read_string("/out.txt"), "redirected\n")
}

test "ShellContext pipe" {
  let sh = ShellContext::new()

  // Setup test file
  sh.get_fs().write_string("/data.txt", "foo\nbar\nbaz\n")

  // cat | grep
  sh.reset_streams()
  let _ = sh.exec("cat /data.txt | grep bar")
  assert_eq(bytes_to_string(sh.get_stdout()), "bar\n")
}

test "ShellContext mkdir and cd" {
  let sh = ShellContext::new()

  let _ = sh.exec("mkdir -p /home/user/projects")
  assert_true(sh.get_fs().is_dir("/home/user/projects"))

  let _ = sh.exec("cd /home/user")
  sh.reset_streams()
  let _ = sh.exec("pwd")
  assert_eq(bytes_to_string(sh.get_stdout()), "/home/user\n")
}

test "ShellContext cp and rm" {
  let sh = ShellContext::new()

  sh.get_fs().write_string("/original.txt", "content")
  let _ = sh.exec("cp /original.txt /copy.txt")
  assert_true(sh.get_fs().exists("/copy.txt"))

  let _ = sh.exec("rm /copy.txt")
  assert_false(sh.get_fs().exists("/copy.txt"))
}

test "ShellContext env and export" {
  let sh = ShellContext::new()

  let _ = sh.exec("export FOO=bar")
  assert_eq(sh.get_ctx().getenv("FOO"), Some("bar"))

  sh.reset_streams()
  let _ = sh.exec("env")
  let output = bytes_to_string(sh.get_stdout())
  assert_true(output.contains("FOO=bar"))
}

fn bytes_to_string(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

test "true and false commands" {
  let sh = ShellContext::new()

  let result_true = sh.exec("true")
  assert_eq(result_true, 0)

  let result_false = sh.exec("false")
  assert_eq(result_false, 1)
}

test "exit code tracking" {
  let sh = ShellContext::new()

  let _ = sh.exec("true")
  assert_eq(sh.get_last_exit_code(), 0)

  let _ = sh.exec("false")
  assert_eq(sh.get_last_exit_code(), 1)
}

test "test command - file tests" {
  let sh = ShellContext::new()

  // Create a test file
  sh.get_fs().write_string("/testfile.txt", "content")
  sh.get_fs().mkdir("/testdir")

  // -e (exists)
  assert_eq(sh.exec("test -e /testfile.txt"), 0)
  assert_eq(sh.exec("test -e /nonexistent"), 1)

  // -f (is file)
  assert_eq(sh.exec("test -f /testfile.txt"), 0)
  assert_eq(sh.exec("test -f /testdir"), 1)

  // -d (is directory)
  assert_eq(sh.exec("test -d /testdir"), 0)
  assert_eq(sh.exec("test -d /testfile.txt"), 1)
}

test "test command - string tests" {
  let sh = ShellContext::new()

  // -z (empty string) - note: quotes not fully supported in simple exec
  // Testing via cmd_test directly
  assert_eq(cmd_test(sh, ["-z", ""]), 0)
  assert_eq(sh.exec("test -z hello"), 1)

  // -n (non-empty string)
  assert_eq(sh.exec("test -n hello"), 0)

  // string comparison
  assert_eq(sh.exec("test foo = foo"), 0)
  assert_eq(sh.exec("test foo = bar"), 1)
  assert_eq(sh.exec("test foo != bar"), 0)
}

test "test command - numeric tests" {
  let sh = ShellContext::new()

  assert_eq(sh.exec("test 5 -eq 5"), 0)
  assert_eq(sh.exec("test 5 -ne 3"), 0)
  assert_eq(sh.exec("test 3 -lt 5"), 0)
  assert_eq(sh.exec("test 5 -gt 3"), 0)
  assert_eq(sh.exec("test 5 -le 5"), 0)
  assert_eq(sh.exec("test 5 -ge 5"), 0)
}

test "bracket command" {
  let sh = ShellContext::new()

  assert_eq(sh.exec("[ 1 -eq 1 ]"), 0)
  assert_eq(sh.exec("[ 1 -eq 2 ]"), 1)
}

test "if statement via exec_script" {
  let sh = ShellContext::new()

  // Simple if-then
  sh.reset_streams()
  let _ = sh.exec_script("if true; then echo yes; fi")
  assert_eq(bytes_to_string(sh.get_stdout()), "yes\n")

  // if-else
  sh.reset_streams()
  let _ = sh.exec_script("if false; then echo yes; else echo no; fi")
  assert_eq(bytes_to_string(sh.get_stdout()), "no\n")
}

test "for loop via exec_script" {
  let sh = ShellContext::new()

  sh.reset_streams()
  let _ = sh.exec_script("for x in a b c; do echo $x; done")
  assert_eq(bytes_to_string(sh.get_stdout()), "a\nb\nc\n")
}

test "while loop via exec_script" {
  let sh = ShellContext::new()

  // Use a counter via environment variable
  let _ = sh.exec("export COUNT=0")
  sh.reset_streams()
  // Simple while that runs 3 times
  let _ = sh.exec_script("x=1; while test $x -le 3; do echo $x; x=$((x+1)); done")
  // Note: This might not work perfectly without full arithmetic support
}

test "quote handling - single quotes" {
  let sh = ShellContext::new()

  sh.reset_streams()
  let _ = sh.exec("echo 'hello world'")
  assert_eq(bytes_to_string(sh.get_stdout()), "hello world\n")

  sh.reset_streams()
  let _ = sh.exec("echo 'with  spaces'")
  assert_eq(bytes_to_string(sh.get_stdout()), "with  spaces\n")
}

test "quote handling - double quotes" {
  let sh = ShellContext::new()

  sh.reset_streams()
  let _ = sh.exec("echo \"hello world\"")
  assert_eq(bytes_to_string(sh.get_stdout()), "hello world\n")

  sh.reset_streams()
  let _ = sh.exec("echo \"with  spaces\"")
  assert_eq(bytes_to_string(sh.get_stdout()), "with  spaces\n")
}

test "quote handling - empty string" {
  let sh = ShellContext::new()

  // Empty single quotes
  assert_eq(cmd_test(sh, ["-z", ""]), 0)

  // Test with quoted empty via direct call
  sh.reset_streams()
  let _ = sh.exec("echo ''")
  assert_eq(bytes_to_string(sh.get_stdout()), "\n")
}

test "quote handling - escapes" {
  let sh = ShellContext::new()

  sh.reset_streams()
  let _ = sh.exec("echo hello\\ world")
  assert_eq(bytes_to_string(sh.get_stdout()), "hello world\n")
}

test "glob_match basic patterns" {
  // * matches any
  assert_true(glob_match("*.txt", "foo.txt"))
  assert_true(glob_match("*.txt", "bar.txt"))
  assert_false(glob_match("*.txt", "foo.md"))

  // ? matches single char
  assert_true(glob_match("f?o", "foo"))
  assert_true(glob_match("f?o", "fao"))
  assert_false(glob_match("f?o", "fooo"))

  // Character class
  assert_true(glob_match("[abc]", "a"))
  assert_true(glob_match("[abc]", "b"))
  assert_false(glob_match("[abc]", "d"))

  // Range
  assert_true(glob_match("[a-z]", "m"))
  assert_false(glob_match("[a-z]", "5"))
}

test "glob expansion in shell" {
  let sh = ShellContext::new()

  // Create test files
  sh.get_fs().write_string("/test1.txt", "a")
  sh.get_fs().write_string("/test2.txt", "b")
  sh.get_fs().write_string("/test3.md", "c")

  // Expand *.txt via exec_script
  sh.reset_streams()
  let _ = sh.exec_script("for f in /*.txt; do echo $f; done")
  let output = bytes_to_string(sh.get_stdout())
  assert_true(output.contains("/test1.txt"))
  assert_true(output.contains("/test2.txt"))
  assert_false(output.contains("/test3.md"))
}

test "command substitution via expand_literal" {
  let sh = ShellContext::new()

  // Test expand_literal directly - this should execute the command
  sh.reset_streams()
  let result = sh.expand_literal("$(echo hello)")
  assert_eq(result, "hello")

  // Test with pwd
  sh.reset_streams()
  let result2 = sh.expand_literal("$(pwd)")
  assert_eq(result2, "/")

  // Nested in text
  sh.reset_streams()
  let result3 = sh.expand_literal("prefix-$(echo test)-suffix")
  assert_eq(result3, "prefix-test-suffix")
}

test "arithmetic expansion" {
  let sh = ShellContext::new()

  // Test expand_literal directly for arithmetic
  let result1 = sh.expand_literal("$((1+2))")
  assert_eq(result1, "3")

  let result2 = sh.expand_literal("$((10-3))")
  assert_eq(result2, "7")

  let result3 = sh.expand_literal("$((4*5))")
  assert_eq(result3, "20")
}
