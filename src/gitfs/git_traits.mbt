///| Implement bit FileSystem and RepoFileSystem traits

///|
/// Implement bit.FileSystem (write operations)
pub impl @types.FileSystem for GitBackedFs with fn mkdir_p(self, path) {
  self.memfs.mkdir_p(path) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
pub impl @types.FileSystem for GitBackedFs with fn write_file(self, path, data) {
  self.memfs.write_file(path, data) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
pub impl @types.FileSystem for GitBackedFs with fn write_string(
  self,
  path,
  content,
) {
  self.memfs.write_string(path, content) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
pub impl @types.FileSystem for GitBackedFs with fn remove_file(self, path) {
  self.memfs.remove(path) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
pub impl @types.FileSystem for GitBackedFs with fn remove_dir(self, path) {
  self.memfs.rmdir(path) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
/// Implement bit.RepoFileSystem (read operations)
pub impl @types.RepoFileSystem for GitBackedFs with fn read_file(self, path) {
  self.memfs.read_file(path) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
}

///|
pub impl @types.RepoFileSystem for GitBackedFs with fn readdir(self, path) {
  let entries = self.memfs.readdir(path) catch {
    e => raise @types.GitError::IoError(e.to_string())
  }
  entries.map(fn(e) { e.name })
}

///|
pub impl @types.RepoFileSystem for GitBackedFs with fn is_dir(self, path) {
  self.memfs.is_dir(path)
}

///|
pub impl @types.RepoFileSystem for GitBackedFs with fn is_file(self, path) {
  self.memfs.is_file(path)
}

///|
pub impl @types.RepoFileSystem for GitBackedFs with fn mtime(_self, _path) {
  (0, 0)
}
