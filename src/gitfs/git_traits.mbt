///| Implement git FileSystem and RepoFileSystem traits

///| Implement git.FileSystem (write operations)
pub impl @git.FileSystem for GitBackedFs with mkdir_p(self, path) {
  self.memfs.mkdir_p(path) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

pub impl @git.FileSystem for GitBackedFs with write_file(self, path, data) {
  self.memfs.write_file(path, data) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

pub impl @git.FileSystem for GitBackedFs with write_string(self, path, content) {
  self.memfs.write_string(path, content) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

pub impl @git.FileSystem for GitBackedFs with remove_file(self, path) {
  self.memfs.remove(path) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

pub impl @git.FileSystem for GitBackedFs with remove_dir(self, path) {
  self.memfs.rmdir(path) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

///| Implement git.RepoFileSystem (read operations)
pub impl @git.RepoFileSystem for GitBackedFs with read_file(self, path) {
  self.memfs.read_file(path) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
}

pub impl @git.RepoFileSystem for GitBackedFs with readdir(self, path) {
  let entries = self.memfs.readdir(path) catch {
    e => raise @git.GitError::IoError(e.to_string())
  }
  entries.map(fn(e) { e.name })
}

pub impl @git.RepoFileSystem for GitBackedFs with is_dir(self, path) {
  self.memfs.is_dir(path)
}

pub impl @git.RepoFileSystem for GitBackedFs with is_file(self, path) {
  self.memfs.is_file(path)
}
