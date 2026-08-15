///| FileSystemBackend implementation for GitBackedFs

///|
/// Implement moonix FileSystemBackend trait
pub impl @fs.FileSystemBackend for GitBackedFs with fn read_file(self, path) {
  @fs.FileSystemBackend::read_file(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn read_string(self, path) {
  @fs.FileSystemBackend::read_string(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn exists(self, path) {
  @fs.FileSystemBackend::exists(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn is_file(self, path) {
  @fs.FileSystemBackend::is_file(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn is_dir(self, path) {
  @fs.FileSystemBackend::is_dir(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn stat(self, path) {
  @fs.FileSystemBackend::stat(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn readdir(self, path) {
  @fs.FileSystemBackend::readdir(self.memfs, path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn write_file(
  self,
  path,
  data,
) {
  @fs.FileSystemBackend::write_file(self.memfs, path, data)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn write_string(
  self,
  path,
  content,
) {
  @fs.FileSystemBackend::write_string(self.memfs, path, content)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn mkdir(self, path) {
  @fs.FileSystemBackend::mkdir(self.memfs, path)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn mkdir_p(self, path) {
  @fs.FileSystemBackend::mkdir_p(self.memfs, path)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn remove(self, path) {
  @fs.FileSystemBackend::remove(self.memfs, path)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn rmdir(self, path) {
  @fs.FileSystemBackend::rmdir(self.memfs, path)
  self.mark_dirty(path)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn rename(self, from, to) {
  @fs.FileSystemBackend::rename(self.memfs, from, to)
  self.mark_dirty(from)
  self.mark_dirty(to)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn copy_file(self, from, to) {
  @fs.FileSystemBackend::copy_file(self.memfs, from, to)
  self.mark_dirty(to)
}

///|
pub impl @fs.FileSystemBackend for GitBackedFs with fn rm_rf(self, path) {
  @fs.FileSystemBackend::rm_rf(self.memfs, path)
  self.mark_dirty(path)
}
