///| Backward-compatible facade for Preview2 WASI filesystem adapter.

///|

///|
/// New code should prefer `@wasi_posix`.
pub struct WasiFs {
  inner : @wasi_posix.WasiFs
}

///|
pub fn WasiFs::new(root : @wasi_fs.Descriptor) -> WasiFs {
  { inner: @wasi_posix.WasiFs::from_p2(root) }
}

///|
pub impl @fs.FileSystemBackend for WasiFs with read_file(self, path) {
  @fs.FileSystemBackend::read_file(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with read_string(self, path) {
  @fs.FileSystemBackend::read_string(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with exists(self, path) {
  @fs.FileSystemBackend::exists(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with is_file(self, path) {
  @fs.FileSystemBackend::is_file(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with is_dir(self, path) {
  @fs.FileSystemBackend::is_dir(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with stat(self, path) {
  @fs.FileSystemBackend::stat(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with readdir(self, path) {
  @fs.FileSystemBackend::readdir(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with write_file(self, path, data) {
  @fs.FileSystemBackend::write_file(self.inner, path, data)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with write_string(self, path, content) {
  @fs.FileSystemBackend::write_string(self.inner, path, content)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with mkdir(self, path) {
  @fs.FileSystemBackend::mkdir(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with mkdir_p(self, path) {
  @fs.FileSystemBackend::mkdir_p(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with remove(self, path) {
  @fs.FileSystemBackend::remove(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rmdir(self, path) {
  @fs.FileSystemBackend::rmdir(self.inner, path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rename(self, old_path, new_path) {
  @fs.FileSystemBackend::rename(self.inner, old_path, new_path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with copy_file(self, src, dst) {
  @fs.FileSystemBackend::copy_file(self.inner, src, dst)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rm_rf(self, path) {
  @fs.FileSystemBackend::rm_rf(self.inner, path)
}
