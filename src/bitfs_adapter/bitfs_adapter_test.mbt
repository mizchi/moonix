///| Tests for BitFsAdapter

test "BitFsAdapter basic operations" {
  let repo = @bit.TestFs::new()
  let fs = @bitfs.Fs::empty("/.git", config=@bitfs.FsConfig::local_only())
  let adapter = BitFsAdapter::new(fs, repo)

  adapter.mkdir_p("/home/user")
  adapter.write_string("/home/user/file.txt", "hello")

  assert_true(adapter.exists("/home/user/file.txt"))
  assert_true(adapter.is_file("/home/user/file.txt"))
  assert_true(adapter.is_dir("/home"))
  assert_eq(adapter.read_string("/home/user/file.txt"), "hello")

  let stat = adapter.stat("/home/user/file.txt")
  assert_eq(stat.size, 5)
  assert_eq(stat.file_type, @fs.FileType::File)

  let root_entries = adapter.readdir("/")
  assert_eq(root_entries.length(), 1)
  assert_eq(root_entries[0].name, "home")
  assert_eq(root_entries[0].file_type, @fs.FileType::Directory)

  let home_entries = adapter.readdir("/home/user")
  assert_eq(home_entries.length(), 1)
  assert_eq(home_entries[0].name, "file.txt")
  assert_eq(home_entries[0].file_type, @fs.FileType::File)
}

test "BitFsAdapter rename and rm_rf" {
  let repo = @bit.TestFs::new()
  let fs = @bitfs.Fs::empty("/.git", config=@bitfs.FsConfig::local_only())
  let adapter = BitFsAdapter::new(fs, repo)

  adapter.mkdir_p("/a/b/c")
  adapter.write_string("/a/b/c/file.txt", "data")

  adapter.rename("/a/b/c/file.txt", "/a/b/c/renamed.txt")
  assert_false(adapter.exists("/a/b/c/file.txt"))
  assert_true(adapter.exists("/a/b/c/renamed.txt"))

  adapter.rm_rf("/a")
  assert_false(adapter.exists("/a"))
  assert_false(adapter.exists("/a/b"))
  assert_false(adapter.exists("/a/b/c"))
}
