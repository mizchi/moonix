///| Tests for GitBackedFs

test "GitBackedFs::new initializes git directory" {
  let fs = GitBackedFs::new()
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git"))
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git/objects"))
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git/refs"))
  assert_true(@fs.FileSystemBackend::is_file(fs, "/.git/HEAD"))
}

test "GitBackedFs basic file operations" {
  let fs = GitBackedFs::new()

  // Write file
  @fs.FileSystemBackend::write_string(fs, "/hello.txt", "world")
  assert_true(@fs.FileSystemBackend::exists(fs, "/hello.txt"))
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/hello.txt"), "world")

  // Check dirty tracking
  assert_true(fs.has_changes())
  let dirty = fs.get_dirty_paths()
  assert_true(dirty.contains("/hello.txt"))
}

test "GitBackedFs snapshot and rollback" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })

  // Create initial file
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "version 1")
  let snap1 = fs.snapshot("Initial commit")

  // Modify file
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "version 2")
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/file.txt"), "version 2")

  // Create second snapshot
  let _ = fs.snapshot("Second commit")

  // Rollback to first snapshot
  fs.rollback(snap1)
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/file.txt"), "version 1")
}

test "GitBackedFs history" {
  let fs = GitBackedFs::new(author="test")
  let mut ts = 1000L
  fs.set_timestamp_provider(fn() {
    let t = ts
    ts += 1000L
    t
  })

  // Create commits
  @fs.FileSystemBackend::write_string(fs, "/a.txt", "a")
  let _ = fs.snapshot("First")

  @fs.FileSystemBackend::write_string(fs, "/b.txt", "b")
  let _ = fs.snapshot("Second")

  @fs.FileSystemBackend::write_string(fs, "/c.txt", "c")
  let _ = fs.snapshot("Third")

  // Check history
  let hist = fs.history()
  assert_eq(hist.length(), 3)
  assert_eq(hist[0].message, "Third")
  assert_eq(hist[1].message, "Second")
  assert_eq(hist[2].message, "First")
}

test "GitBackedFs multiple files" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })

  // Create directory structure
  @fs.FileSystemBackend::mkdir_p(fs, "/src/lib")
  @fs.FileSystemBackend::write_string(fs, "/src/main.mbt", "fn main() {}")
  @fs.FileSystemBackend::write_string(fs, "/src/lib/utils.mbt", "fn helper() {}")
  @fs.FileSystemBackend::write_string(fs, "/README.md", "# Project")

  // Snapshot
  let snap = fs.snapshot("Add project files")

  // Delete all
  @fs.FileSystemBackend::rm_rf(fs, "/src")
  @fs.FileSystemBackend::remove(fs, "/README.md")
  assert_false(@fs.FileSystemBackend::exists(fs, "/src"))
  assert_false(@fs.FileSystemBackend::exists(fs, "/README.md"))

  // Rollback
  fs.rollback(snap)
  assert_true(@fs.FileSystemBackend::exists(fs, "/src/main.mbt"))
  assert_true(@fs.FileSystemBackend::exists(fs, "/src/lib/utils.mbt"))
  assert_true(@fs.FileSystemBackend::exists(fs, "/README.md"))
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/src/main.mbt"), "fn main() {}")
}

test "GitBackedFs git paths excluded from dirty tracking" {
  let fs = GitBackedFs::new()

  // Write to .git should not be tracked as dirty
  @fs.FileSystemBackend::write_string(fs, "/.git/config", "[core]")
  assert_false(fs.has_changes())

  // Write to normal path should be tracked
  @fs.FileSystemBackend::write_string(fs, "/normal.txt", "content")
  assert_true(fs.has_changes())
}
