///| Snapshot and rollback operations

///| Create a snapshot (git commit) of current state
pub fn GitBackedFs::snapshot(
  self : GitBackedFs,
  message : String,
) -> SnapshotId raise @git.GitError {
  let timestamp = self.get_timestamp()

  // Collect all working files (excluding .git)
  let files = self.collect_working_files()

  // Stage all files using add_paths
  if files.length() > 0 {
    @lib.add_paths(self, self, self.root, files)
  }

  // Create commit
  let commit_id = @lib.commit(
    self,
    self,
    self.root,
    message,
    self.author,
    timestamp,
  )

  // Update HEAD
  self.head = Some(commit_id)

  // Clear dirty tracking
  self.clear_dirty()

  { commit_id, message, timestamp }
}

///| Collect all files in working tree (excluding .git)
fn GitBackedFs::collect_working_files(self : GitBackedFs) -> Array[String] {
  let files : Array[String] = []
  self.collect_files_recursive(self.root, files)
  files
}

///| Recursively collect files
fn GitBackedFs::collect_files_recursive(
  self : GitBackedFs,
  dir : String,
  files : Array[String],
) -> Unit {
  let entries = @fs.FileSystemBackend::readdir(self.memfs, dir) catch {
    _ => return
  }
  for entry in entries {
    let path = if dir == "/" {
      "/" + entry.name
    } else {
      dir + "/" + entry.name
    }
    // Skip .git directory
    if self.is_git_path(path) {
      continue
    }
    match entry.file_type {
      @fs.Directory => self.collect_files_recursive(path, files)
      @fs.File => {
        // Store relative path (strip leading /)
        // Strip leading "/" for relative path
        let rel_path = if path.has_prefix("/") && path.length() > 1 {
          let chars = path.to_array()
          let mut result = ""
          for i = 1; i < chars.length(); i = i + 1 {
            result = result + chars[i].to_string()
          }
          result
        } else {
          path
        }
        files.push(rel_path)
      }
      _ => continue
    }
  }
}

///| Rollback to a previous snapshot
pub fn GitBackedFs::rollback(
  self : GitBackedFs,
  snapshot : SnapshotId,
) -> Unit raise @git.GitError {
  self.rollback_to(snapshot.commit_id)
}

///| Rollback to a commit by ID
pub fn GitBackedFs::rollback_to(
  self : GitBackedFs,
  commit_id : @git.ObjectId,
) -> Unit raise @git.GitError {
  let _ = @lib.checkout(
    self,
    self,
    self.root,
    commit_id.to_hex(),
    detach=true,
    update_worktree=true,
    update_index=true,
  )
  self.head = Some(commit_id)
  self.clear_dirty()
}

///| Get current HEAD commit
pub fn GitBackedFs::get_head(self : GitBackedFs) -> @git.ObjectId? {
  self.head
}

///| Get commit history
pub fn GitBackedFs::history(
  self : GitBackedFs,
  max_count~ : Int = 100,
) -> Array[SnapshotId] raise @git.GitError {
  let log_entries = @lib.log_head(self, self.git_dir, max_count~)
  log_entries.map(fn(entry) {
    { commit_id: entry.id, message: entry.message, timestamp: entry.timestamp }
  })
}

///| Create a named branch at current HEAD
pub fn GitBackedFs::branch(
  self : GitBackedFs,
  name : String,
) -> Unit raise @git.GitError {
  @lib.create_branch(self, self, self.root, name)
}

///| Switch to a branch
pub fn GitBackedFs::switch(
  self : GitBackedFs,
  name : String,
) -> Unit raise @git.GitError {
  @lib.switch_branch(self, self, self.root, name, checkout=true)
  self.head = @lib.resolve_head_commit(self, self.git_dir)
  self.clear_dirty()
}

///| List branches
pub fn GitBackedFs::list_branches(
  self : GitBackedFs,
) -> Array[String] raise @git.GitError {
  let (_, branches) = @lib.list_branches(self, self.root)
  branches.map(fn(b) { b.name })
}
