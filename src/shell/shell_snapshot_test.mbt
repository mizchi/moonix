fn trim_line(s : String) -> String {
  s.trim().to_string()
}

fn short_hash(hash : String) -> String {
  if hash.length() > 7 {
    String::unsafe_substring(hash, start=0, end=7)
  } else {
    hash
  }
}

test "snapshot/rollup commands update prompt and restore state" {
  let sh = ShellContext::new()

  let _ = sh.exec("write /note.txt v1")
  sh.reset_streams()
  let _ = sh.exec("snapshot first")
  let hash1 = trim_line(bytes_to_string(sh.get_stdout()))
  assert_true(hash1.length() > 0)
  assert_true(sh.prompt().contains(short_hash(hash1)))

  let _ = sh.exec("write /note.txt v2")
  sh.reset_streams()
  let _ = sh.exec("snapshot second")
  let hash2 = trim_line(bytes_to_string(sh.get_stdout()))
  assert_true(hash2 != hash1)
  assert_true(sh.prompt().contains(short_hash(hash2)))

  sh.reset_streams()
  let _ = sh.exec("rollup " + hash1)
  assert_eq(sh.get_fs().read_string("/note.txt"), "v1\n")
  assert_true(sh.prompt().contains(short_hash(hash1)))
}
