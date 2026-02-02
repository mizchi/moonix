///| Git-backed virtual filesystem with snapshot and rollback support

///| Snapshot identifier
pub struct SnapshotId {
  commit_id : @bit.ObjectId
  message : String
  timestamp : Int64
}

///| GitBackedFs - A filesystem backed by git for versioning
pub struct GitBackedFs {
  /// In-memory filesystem for working tree
  memfs : @fs.MemFs
  /// Git directory path (default: "/.git")
  git_dir : String
  /// Working tree root (default: "/")
  root : String
  /// Dirty file tracking (path -> true if modified since last snapshot)
  mut dirty : Map[String, Bool]
  /// Current HEAD commit (None if no commits yet)
  mut head : @bit.ObjectId?
  /// Author name for commits
  author : String
  /// Timestamp provider (for testing)
  mut timestamp_provider : () -> Int64
}

///| Create a new GitBackedFs
pub fn GitBackedFs::new(author~ : String = "moonix") -> GitBackedFs {
  let memfs = @fs.MemFs::new()
  let fs = {
    memfs,
    git_dir: "/.git",
    root: "/",
    dirty: {},
    head: None,
    author,
    timestamp_provider: fn() { 0L }, // TODO: real timestamp
  }
  // Initialize git repository structure
  fs.init_git_dir()
  fs
}

///| Initialize .git directory structure
fn GitBackedFs::init_git_dir(self : GitBackedFs) -> Unit {
  try {
    @lib.init_repo(self, self.root, default_branch="main", bare=false)
  } catch {
    _ => ()
  }
}

///| Set timestamp provider (for testing)
pub fn GitBackedFs::set_timestamp_provider(
  self : GitBackedFs,
  provider : () -> Int64,
) -> Unit {
  self.timestamp_provider = provider
}

///| Get current timestamp
fn GitBackedFs::get_timestamp(self : GitBackedFs) -> Int64 {
  (self.timestamp_provider)()
}

///| Get underlying MemFs (for direct access)
pub fn GitBackedFs::get_memfs(self : GitBackedFs) -> @fs.MemFs {
  self.memfs
}

///| Check if path is inside .git directory
fn GitBackedFs::is_git_path(self : GitBackedFs, path : String) -> Bool {
  let normalized = @fs.normalize_path(path)
  normalized.has_prefix(self.git_dir) || normalized == self.git_dir
}

///| Mark a path as dirty
fn GitBackedFs::mark_dirty(self : GitBackedFs, path : String) -> Unit {
  if not(self.is_git_path(path)) {
    let normalized = @fs.normalize_path(path)
    self.dirty[normalized] = true
  }
}

///| Clear dirty flags
fn GitBackedFs::clear_dirty(self : GitBackedFs) -> Unit {
  self.dirty = {}
}

///| Check if there are uncommitted changes
pub fn GitBackedFs::has_changes(self : GitBackedFs) -> Bool {
  self.dirty.length() > 0
}

///| Get list of dirty paths
pub fn GitBackedFs::get_dirty_paths(self : GitBackedFs) -> Array[String] {
  let paths : Array[String] = []
  for entry in self.dirty {
    paths.push(entry.0)
  }
  paths.sort()
  paths
}
