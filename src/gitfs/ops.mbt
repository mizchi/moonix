///| Git operations: merge, diff, status, tag, stash, reset, cherry_pick

///|
/// Get working tree status (async because bit's status is async)
pub async fn GitBackedFs::status(
  self : GitBackedFs,
) -> @lib.Status raise @bit.GitError {
  @lib.status(self, self.root)
}

///|
/// Push current changes to stash (async because bit's stash_push is async)
pub async fn GitBackedFs::stash(
  self : GitBackedFs,
  message? : String = "",
) -> @bit.ObjectId? raise @bit.GitError {
  let timestamp = self.get_timestamp()
  let result = @lib.stash_push(
    self,
    self,
    self.root,
    message,
    self.author,
    timestamp,
  )
  self.head = @lib.resolve_head_commit(self, self.git_dir)
  self.clear_dirty()
  result
}

///|
/// Merge a branch into current branch
pub fn GitBackedFs::merge(
  self : GitBackedFs,
  branch_name : String,
) -> @lib.MergeResult raise @bit.GitError {
  let ref_name = "refs/heads/" + branch_name
  let target = @lib.resolve_ref(self, self.git_dir, ref_name)
  guard target is Some(target_id) else {
    raise @bit.GitError::IoError("branch not found: " + branch_name)
  }
  let timestamp = self.get_timestamp()
  let message = "Merge branch '" + branch_name + "'"
  let result = @lib.merge(
    self,
    self,
    self.root,
    target_id,
    message,
    self.author,
    timestamp,
  )
  self.head = @lib.resolve_head_commit(self, self.git_dir)
  self.clear_dirty()
  result
}

///|
/// Get diff of working tree vs index
pub fn GitBackedFs::diff(
  self : GitBackedFs,
) -> Array[@lib.DiffFile] raise @bit.GitError {
  @lib.diff_index(self, self.root)
}

///|
/// Get diff as text
pub fn GitBackedFs::diff_text(self : GitBackedFs) -> String raise @bit.GitError {
  let diffs = @lib.diff_index(self, self.root)
  let lines = @lib.diff_text(diffs)
  lines.join("\n")
}

///|
/// Cherry-pick a commit onto current branch
pub fn GitBackedFs::cherry_pick(
  self : GitBackedFs,
  commit_id : @bit.ObjectId,
) -> @lib.CherryPickResult raise @bit.GitError {
  let timestamp = self.get_timestamp()
  let result = @lib.cherry_pick(
    self,
    self,
    self.root,
    commit_id,
    self.author,
    timestamp,
  )
  self.head = @lib.resolve_head_commit(self, self.git_dir)
  self.clear_dirty()
  result
}

///|
/// Reset current branch to a commit
pub fn GitBackedFs::reset(
  self : GitBackedFs,
  commit_id : @bit.ObjectId,
  mode? : @lib.ResetMode = Mixed,
) -> @bit.ObjectId raise @bit.GitError {
  let result = @lib.reset(self, self, self.root, commit_id.to_hex(), mode)
  self.head = @lib.resolve_head_commit(self, self.git_dir)
  self.clear_dirty()
  result
}

///|
/// Create a lightweight tag at HEAD
pub fn GitBackedFs::tag(
  self : GitBackedFs,
  name : String,
) -> Unit raise @bit.GitError {
  guard self.head is Some(head_id) else {
    raise @bit.GitError::IoError("HEAD is not set")
  }
  @lib.create_lightweight_tag(self, self.git_dir, name, head_id)
}

///|
/// Create a lightweight tag at a specific commit
pub fn GitBackedFs::tag_at(
  self : GitBackedFs,
  name : String,
  commit_id : @bit.ObjectId,
) -> Unit raise @bit.GitError {
  @lib.create_lightweight_tag(self, self.git_dir, name, commit_id)
}

///|
/// Delete a tag
pub fn GitBackedFs::delete_tag(
  self : GitBackedFs,
  name : String,
) -> Unit raise @bit.GitError {
  @lib.delete_tag(self, self.git_dir, name)
}

///|
/// List all tags
pub fn GitBackedFs::list_tags(self : GitBackedFs) -> Array[String] {
  @lib.list_tags(self, self.git_dir)
}

///|
/// Apply a stash entry (keep it in stash list)
pub fn GitBackedFs::stash_apply(
  self : GitBackedFs,
  index? : Int = 0,
) -> Unit raise @bit.GitError {
  @lib.stash_apply(self, self, self.root, index, false)
  self.clear_dirty()
}

///|
/// Pop a stash entry (apply and drop)
pub fn GitBackedFs::stash_pop(
  self : GitBackedFs,
  index? : Int = 0,
) -> Unit raise @bit.GitError {
  @lib.stash_apply(self, self, self.root, index, true)
  self.clear_dirty()
}

///|
/// Drop a stash entry
pub fn GitBackedFs::stash_drop(
  self : GitBackedFs,
  index? : Int = 0,
) -> Unit raise @bit.GitError {
  @lib.stash_drop(self, self, self.root, index)
}

///|
/// List all stash entries
pub fn GitBackedFs::stash_list(
  self : GitBackedFs,
) -> Array[@lib.StashEntry] raise @bit.GitError {
  @lib.stash_list(self, self.root)
}
