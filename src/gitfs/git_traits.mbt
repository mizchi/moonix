///| Implement bit FileSystem and RepoFileSystem traits

///| Implement bit.FileSystem (write operations)
pub impl @bit.FileSystem for GitBackedFs with mkdir_p(self, path) {
  self.memfs.mkdir_p(path) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

pub impl @bit.FileSystem for GitBackedFs with write_file(self, path, data) {
  self.memfs.write_file(path, data) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

pub impl @bit.FileSystem for GitBackedFs with write_string(self, path, content) {
  self.memfs.write_string(path, content) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

pub impl @bit.FileSystem for GitBackedFs with remove_file(self, path) {
  self.memfs.remove(path) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

pub impl @bit.FileSystem for GitBackedFs with remove_dir(self, path) {
  self.memfs.rmdir(path) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

///| Implement bit.RepoFileSystem (read operations)
pub impl @bit.RepoFileSystem for GitBackedFs with read_file(self, path) {
  self.memfs.read_file(path) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
}

pub impl @bit.RepoFileSystem for GitBackedFs with readdir(self, path) {
  let entries = self.memfs.readdir(path) catch {
    e => raise @bit.GitError::IoError(e.to_string())
  }
  entries.map(fn(e) { e.name })
}

pub impl @bit.RepoFileSystem for GitBackedFs with is_dir(self, path) {
  self.memfs.is_dir(path)
}

pub impl @bit.RepoFileSystem for GitBackedFs with is_file(self, path) {
  self.memfs.is_file(path)
}
