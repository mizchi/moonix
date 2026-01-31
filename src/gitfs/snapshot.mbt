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
  // Get current working files before checkout
  let current_files = self.collect_working_files()

  // Get target tree files
  let db = @lib.ObjectDb::load(self, self.git_dir)
  let target_files = @lib.collect_tree_files_from_commit(db, self, commit_id)

  // Perform checkout (restores tracked files)
  let _ = @lib.checkout(
    self,
    self,
    self.root,
    commit_id.to_hex(),
    detach=true,
    update_worktree=true,
    update_index=true,
  )

  // Remove untracked files (files that exist in working dir but not in target)
  for file in current_files {
    if not(target_files.contains(file)) {
      let abs_path = if self.root == "/" {
        "/" + file
      } else {
        self.root + "/" + file
      }
      if self.memfs.is_file(abs_path) {
        @fs.FileSystemBackend::remove(self.memfs, abs_path) catch {
          _ => () // Ignore errors
        }
      }
    }
  }

  // Clean up empty directories
  self.clean_empty_directories(self.root)

  self.head = Some(commit_id)
  self.clear_dirty()
}

///| Remove empty directories recursively
fn GitBackedFs::clean_empty_directories(self : GitBackedFs, dir : String) -> Unit {
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
      @fs.Directory => {
        // Recursively clean subdirectories first
        self.clean_empty_directories(path)
        // Try to remove if now empty
        let sub_entries = @fs.FileSystemBackend::readdir(self.memfs, path) catch {
          _ => continue
        }
        if sub_entries.length() == 0 {
          @fs.FileSystemBackend::remove(self.memfs, path) catch {
            _ => () // Ignore errors
          }
        }
      }
      _ => ()
    }
  }
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

///| Create a branch at a specific commit
pub fn GitBackedFs::branch_at(
  self : GitBackedFs,
  name : String,
  commit_id : @git.ObjectId,
) -> Unit raise @git.GitError {
  @lib.create_branch_at(self, self, self.root, name, commit_id)
}

///| Get current branch name (None if detached HEAD)
pub fn GitBackedFs::current_branch(self : GitBackedFs) -> String? raise @git.GitError {
  let head_ref = @lib.read_head_ref(self, self.git_dir)
  match head_ref {
    @lib.Branch(name) => Some(name)
    @lib.Detached(_) => None
  }
}

///| List branches
pub fn GitBackedFs::list_branches(
  self : GitBackedFs,
) -> Array[String] raise @git.GitError {
  let (_, branches) = @lib.list_branches(self, self.root)
  branches.map(fn(b) { b.name })
}
