///| Adapter: mizchi/bit/x/fs -> moonix FileSystemBackend

///|
/// BitFsAdapter wraps bitfs.Fs with a RepoFileSystem to implement FileSystemBackend.
pub struct BitFsAdapter {
  fs : @bitfs.Fs
  repo : &@bit.RepoFileSystem
}

///|
/// Create a new adapter
pub fn BitFsAdapter::new(
  fs : @bitfs.Fs,
  repo : &@bit.RepoFileSystem,
) -> BitFsAdapter {
  { fs, repo }
}

///|
/// Get underlying bitfs instance
pub fn BitFsAdapter::get_fs(self : BitFsAdapter) -> @bitfs.Fs {
  self.fs
}

///|
fn to_rel_path(path : String) -> String {
  let normalized = @fs.normalize_path(path)
  if normalized == "/" {
    ""
  } else if normalized.has_prefix("/") {
    String::unsafe_substring(normalized, start=1, end=normalized.length())
  } else {
    normalized
  }
}

///|
fn join_rel(dir : String, name : String) -> String {
  if dir.length() == 0 {
    name
  } else {
    dir + "/" + name
  }
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  let buf = StringBuilder::new()
  for b in bytes {
    buf.write_char(b.to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
fn string_to_bytes(content : String) -> Bytes {
  Bytes::from_array(
    FixedArray::makei(content.length(), fn(i) { content[i].to_int().to_byte() }),
  )
}

///|
fn BitFsAdapter::ensure_parent_dir(
  self : BitFsAdapter,
  abs_path : String,
) -> Unit raise @fs.FsError {
  let parent = @fs.parent_path(abs_path)
  if parent == "/" {
    return
  }
  if self.is_file(parent) {
    raise @fs.FsError::NotADirectory(parent)
  }
  if not(self.is_dir(parent)) {
    raise @fs.FsError::NotFound(parent)
  }
}

///|
fn BitFsAdapter::check_no_file_in_path(
  self : BitFsAdapter,
  abs_path : String,
) -> Unit raise @fs.FsError {
  let rel = to_rel_path(abs_path)
  if rel.length() == 0 {
    return
  }
  let mut current = ""
  for part_view in rel.split("/") {
    let part = part_view.to_string()
    if part.length() == 0 {
      continue
    }
    current = if current.length() == 0 { part } else { current + "/" + part }
    let abs_current = "/" + current
    if self.is_file(abs_current) {
      raise @fs.FsError::NotADirectory(abs_current)
    }
  }
}

///|
fn git_error_to_fs(err : @bit.GitError) -> @fs.FsError {
  @fs.FsError::IoError(err.to_string())
}

///|
/// FileSystemBackend implementation
pub impl @fs.FileSystemBackend for BitFsAdapter with read_file(self, path) {
  let abs = @fs.normalize_path(path)
  if self.is_dir(abs) {
    raise @fs.FsError::IsADirectory(path)
  }
  if not(self.is_file(abs)) {
    raise @fs.FsError::NotFound(path)
  }
  let rel = to_rel_path(abs)
  self.fs.read_file(self.repo, rel) catch {
    e => raise git_error_to_fs(e)
  }
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with read_string(self, path) {
  bytes_to_string(self.read_file(path))
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with exists(self, path) {
  let abs = @fs.normalize_path(path)
  self.is_file(abs) || self.is_dir(abs)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with is_file(self, path) {
  let rel = to_rel_path(path)
  self.fs.is_file(self.repo, rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with is_dir(self, path) {
  let rel = to_rel_path(path)
  self.fs.is_dir(self.repo, rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with stat(self, path) {
  let abs = @fs.normalize_path(path)
  if self.is_file(abs) {
    let data = self.read_file(abs)
    @fs.FileStat::{ file_type: @fs.FileType::File, size: data.length() }
  } else if self.is_dir(abs) {
    @fs.FileStat::{ file_type: @fs.FileType::Directory, size: 0 }
  } else {
    raise @fs.FsError::NotFound(path)
  }
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with readdir(self, path) {
  let abs = @fs.normalize_path(path)
  if not(self.is_dir(abs)) {
    if self.is_file(abs) {
      raise @fs.FsError::NotADirectory(path)
    }
    raise @fs.FsError::NotFound(path)
  }
  let rel = to_rel_path(abs)
  let entries = self.fs.readdir(self.repo, rel) catch {
    e => raise git_error_to_fs(e)
  }
  let out : Array[@fs.DirEntry] = []
  for name in entries {
    let child_rel = join_rel(rel, name)
    let file_type = if self.fs.is_dir(self.repo, child_rel) {
      @fs.FileType::Directory
    } else {
      @fs.FileType::File
    }
    out.push(@fs.DirEntry::{ name, file_type })
  }
  out
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with write_file(
  self,
  path,
  data,
) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    raise @fs.FsError::IsADirectory(path)
  }
  if self.is_dir(abs) {
    raise @fs.FsError::IsADirectory(path)
  }
  self.ensure_parent_dir(abs)
  let rel = to_rel_path(abs)
  self.fs.write_file(rel, data)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with write_string(
  self,
  path,
  content,
) {
  self.write_file(path, string_to_bytes(content))
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with mkdir(self, path) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    raise @fs.FsError::AlreadyExists(path)
  }
  if self.exists(abs) {
    raise @fs.FsError::AlreadyExists(path)
  }
  self.ensure_parent_dir(abs)
  let rel = to_rel_path(abs)
  self.fs.mkdir_p(rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with mkdir_p(self, path) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    return
  }
  self.check_no_file_in_path(abs)
  let rel = to_rel_path(abs)
  self.fs.mkdir_p(rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with remove(self, path) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    raise @fs.FsError::PermissionDenied("cannot remove root")
  }
  if self.is_dir(abs) {
    raise @fs.FsError::IsADirectory(path)
  }
  if not(self.is_file(abs)) {
    raise @fs.FsError::NotFound(path)
  }
  let rel = to_rel_path(abs)
  self.fs.remove_file(rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with rmdir(self, path) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    raise @fs.FsError::PermissionDenied("cannot remove root")
  }
  if self.is_file(abs) {
    raise @fs.FsError::NotADirectory(path)
  }
  if not(self.is_dir(abs)) {
    raise @fs.FsError::NotFound(path)
  }
  let entries = self.readdir(abs)
  if entries.length() > 0 {
    raise @fs.FsError::NotEmpty(path)
  }
  let rel = to_rel_path(abs)
  self.fs.remove_dir(rel)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with rename(
  self,
  old_path,
  new_path,
) {
  let old_abs = @fs.normalize_path(old_path)
  let new_abs = @fs.normalize_path(new_path)
  if old_abs == new_abs {
    return
  }
  if self.is_file(old_abs) {
    let data = self.read_file(old_abs)
    self.write_file(new_abs, data)
    self.remove(old_abs)
  } else if self.is_dir(old_abs) {
    raise @fs.FsError::IoError("directory rename not yet implemented")
  } else {
    raise @fs.FsError::NotFound(old_path)
  }
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with copy_file(self, src, dst) {
  let src_abs = @fs.normalize_path(src)
  let dst_abs = @fs.normalize_path(dst)
  if not(self.is_file(src_abs)) {
    if self.is_dir(src_abs) {
      raise @fs.FsError::IsADirectory(src)
    }
    raise @fs.FsError::NotFound(src)
  }
  let data = self.read_file(src_abs)
  self.write_file(dst_abs, data)
}

///|
pub impl @fs.FileSystemBackend for BitFsAdapter with rm_rf(self, path) {
  let abs = @fs.normalize_path(path)
  if abs == "/" {
    raise @fs.FsError::PermissionDenied("cannot remove root")
  }
  if not(self.exists(abs)) {
    raise @fs.FsError::NotFound(path)
  }
  if self.is_file(abs) {
    self.remove(abs)
    return
  }
  let entries = self.readdir(abs)
  for entry in entries {
    let child = abs + "/" + entry.name
    self.rm_rf(child)
  }
  self.rmdir(abs)
}
