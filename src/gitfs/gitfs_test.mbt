///|
/// Tests for GitBackedFs
test "GitBackedFs::new initializes git directory" {
  let fs = GitBackedFs::new()
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git"))
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git/objects"))
  assert_true(@fs.FileSystemBackend::is_dir(fs, "/.git/refs"))
  assert_true(@fs.FileSystemBackend::is_file(fs, "/.git/HEAD"))
}

///|
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

///|
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

///|
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

///|
test "GitBackedFs multiple files" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })

  // Create directory structure
  @fs.FileSystemBackend::mkdir_p(fs, "/src/lib")
  @fs.FileSystemBackend::write_string(fs, "/src/main.mbt", "fn main() {}")
  @fs.FileSystemBackend::write_string(
    fs, "/src/lib/utils.mbt", "fn helper() {}",
  )
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
  assert_eq(
    @fs.FileSystemBackend::read_string(fs, "/src/main.mbt"),
    "fn main() {}",
  )
}

///|
test "GitBackedFs git paths excluded from dirty tracking" {
  let fs = GitBackedFs::new()

  // Write to .git should not be tracked as dirty
  @fs.FileSystemBackend::write_string(fs, "/.git/config", "[core]")
  assert_false(fs.has_changes())

  // Write to normal path should be tracked
  @fs.FileSystemBackend::write_string(fs, "/normal.txt", "content")
  assert_true(fs.has_changes())
}

///|
test "GitBackedFs tag operations" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "content")
  let _ = fs.snapshot("Initial")

  // No tags initially
  assert_eq(fs.list_tags().length(), 0)

  // Create tag at HEAD
  fs.tag("v1.0")
  let tags = fs.list_tags()
  assert_eq(tags.length(), 1)
  assert_true(tags.contains("v1.0"))

  // Create tag at specific commit
  let head = fs.get_head()
  guard head is Some(commit_id)
  fs.tag_at("v1.0-alias", commit_id)
  assert_eq(fs.list_tags().length(), 2)

  // Delete tag
  fs.delete_tag("v1.0")
  let tags2 = fs.list_tags()
  assert_eq(tags2.length(), 1)
  assert_true(tags2.contains("v1.0-alias"))
}

///|
test "GitBackedFs merge" {
  let fs = GitBackedFs::new(author="test")
  let mut ts = 1000L
  fs.set_timestamp_provider(fn() {
    let t = ts
    ts += 1000L
    t
  })

  // Create initial commit on main
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "initial")
  let _ = fs.snapshot("Initial")

  // Create feature branch and add a file
  fs.branch("feature")
  fs.switch("feature")
  @fs.FileSystemBackend::write_string(fs, "/feature.txt", "new feature")
  let _ = fs.snapshot("Add feature")

  // Switch back to main
  fs.switch("main")
  assert_false(@fs.FileSystemBackend::exists(fs, "/feature.txt"))

  // Merge feature into main
  let result = fs.merge("feature")
  guard result.status is (FastForward | Merged)
  assert_true(@fs.FileSystemBackend::exists(fs, "/feature.txt"))
  assert_eq(
    @fs.FileSystemBackend::read_string(fs, "/feature.txt"),
    "new feature",
  )
}

///|
test "GitBackedFs diff" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })

  // Create initial commit
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "original")
  let _ = fs.snapshot("Initial")

  // Modify file (stage it so diff_index can see it)
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "modified")
  @lib.add_paths(fs, fs, "/", ["file.txt"])
  let diffs = fs.diff()
  assert_true(diffs.length() > 0)
}

///|
test "GitBackedFs reset" {
  let fs = GitBackedFs::new(author="test")
  let mut ts = 1000L
  fs.set_timestamp_provider(fn() {
    let t = ts
    ts += 1000L
    t
  })
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "v1")
  let snap1 = fs.snapshot("First")
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "v2")
  let _ = fs.snapshot("Second")

  // Reset to first commit (hard)
  let _ = fs.reset(snap1.commit_id, mode=Hard)
  assert_eq(@fs.FileSystemBackend::read_string(fs, "/file.txt"), "v1")
}

///|
test "GitBackedFs cherry_pick" {
  let fs = GitBackedFs::new(author="test")
  let mut ts = 1000L
  fs.set_timestamp_provider(fn() {
    let t = ts
    ts += 1000L
    t
  })

  // Create initial commit on main
  @fs.FileSystemBackend::write_string(fs, "/file.txt", "initial")
  let _ = fs.snapshot("Initial")

  // Create feature branch with a commit
  fs.branch("feature")
  fs.switch("feature")
  @fs.FileSystemBackend::write_string(fs, "/cherry.txt", "cherry content")
  let feature_snap = fs.snapshot("Cherry commit")

  // Switch back to main
  fs.switch("main")

  // Cherry-pick the feature commit
  let result = fs.cherry_pick(feature_snap.commit_id)
  guard result.status is Success
  // Cherry-pick updates the tree and creates a new commit,
  // verify commit was created
  assert_true(result.commit_id is Some(_))
}

///|
test "GitBackedFs snapshot handles deep tree and many files" {
  let fs = GitBackedFs::new(author="test")
  fs.set_timestamp_provider(fn() { 1000L })
  let deep_files : Array[(String, String)] = []
  @fs.FileSystemBackend::mkdir_p(fs, "/deep")
  let mut deep_path = "/deep"
  let depth = 20
  for i in 0..<depth {
    deep_path = deep_path + "/d" + i.to_string()
    @fs.FileSystemBackend::mkdir_p(fs, deep_path)
    let path = deep_path + "/file" + i.to_string() + ".txt"
    let content = "depth " + i.to_string()
    @fs.FileSystemBackend::write_string(fs, path, content)
    deep_files.push((path, content))
  }
  let bulk_files : Array[(String, String)] = []
  @fs.FileSystemBackend::mkdir_p(fs, "/bulk")
  let bulk_count = 200
  for i in 0..<bulk_count {
    let path = "/bulk/f" + i.to_string() + ".txt"
    let content = "data " + i.to_string()
    @fs.FileSystemBackend::write_string(fs, path, content)
    bulk_files.push((path, content))
  }
  let snap = fs.snapshot("big tree")
  @fs.FileSystemBackend::rm_rf(fs, "/deep/d0")
  assert_false(@fs.FileSystemBackend::exists(fs, deep_files[0].0))
  for i in 0..<10 {
    let path = bulk_files[i].0
    @fs.FileSystemBackend::write_string(fs, path, "mutated")
  }
  for i in 10..<60 {
    let path = bulk_files[i].0
    @fs.FileSystemBackend::remove(fs, path)
  }
  @fs.FileSystemBackend::write_string(fs, "/bulk/new.txt", "new")
  fs.rollback(snap)
  assert_false(@fs.FileSystemBackend::exists(fs, "/bulk/new.txt"))
  for _, entry in deep_files {
    let (path, content) = entry
    assert_true(@fs.FileSystemBackend::is_file(fs, path))
    assert_eq(@fs.FileSystemBackend::read_string(fs, path), content)
  }
  for _, entry in bulk_files {
    let (path, content) = entry
    assert_true(@fs.FileSystemBackend::is_file(fs, path))
    assert_eq(@fs.FileSystemBackend::read_string(fs, path), content)
  }
}
