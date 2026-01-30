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
