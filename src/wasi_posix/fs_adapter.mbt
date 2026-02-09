///|
/// FileSystemBackend adapter over `WasiFsHost` contract.
pub struct WasiFs {
  host : &WasiFsHost
}

///|
pub fn WasiFs::new(host : &WasiFsHost) -> WasiFs {
  { host, }
}

///|
pub fn WasiFs::from_p2(root : @wasi_fs.Descriptor) -> WasiFs {
  let host = WasiPreview2FsHost::new(root)
  { host: host as &WasiFsHost }
}

///|
fn node_type_to_file_type(t : WasiNodeType) -> @fs.FileType {
  match t {
    File => @fs.FileType::File
    Directory => @fs.FileType::Directory
    Symlink => @fs.FileType::Symlink
    Other => @fs.FileType::File
  }
}

///|
fn bytes_to_string(data : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in data {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
fn string_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}

///|
fn rm_rf_host(host : &WasiFsHost, path : String) -> Unit raise @fs.FsError {
  if not(host.exists(path)) {
    return
  }
  let s = host.stat(path)
  if s.node_type == Directory {
    let entries = host.readdir(path)
    for entry in entries {
      let child = if path == "/" {
        "/" + entry.name
      } else {
        path + "/" + entry.name
      }
      rm_rf_host(host, child)
    }
    if path != "/" {
      host.rmdir(path)
    }
  } else {
    host.remove(path)
  }
}

///|
pub impl @fs.FileSystemBackend for WasiFs with read_file(self, path) {
  self.host.read_file(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with read_string(self, path) {
  let data = self.host.read_file(path)
  bytes_to_string(data)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with exists(self, path) {
  self.host.exists(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with is_file(self, path) {
  let st = self.host.stat(path) catch { _ => return false }
  st.node_type == File
}

///|
pub impl @fs.FileSystemBackend for WasiFs with is_dir(self, path) {
  let st = self.host.stat(path) catch { _ => return false }
  st.node_type == Directory
}

///|
pub impl @fs.FileSystemBackend for WasiFs with stat(self, path) {
  let s = self.host.stat(path)
  { file_type: node_type_to_file_type(s.node_type), size: s.size }
}

///|
pub impl @fs.FileSystemBackend for WasiFs with readdir(self, path) {
  self.host
  .readdir(path)
  .map(fn(entry) {
    { name: entry.name, file_type: node_type_to_file_type(entry.node_type) }
  })
}

///|
pub impl @fs.FileSystemBackend for WasiFs with write_file(self, path, data) {
  self.host.write_file(path, data)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with write_string(self, path, content) {
  self.host.write_file(path, string_to_bytes(content))
}

///|
pub impl @fs.FileSystemBackend for WasiFs with mkdir(self, path) {
  self.host.mkdir(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with mkdir_p(self, path) {
  self.host.mkdir_p(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with remove(self, path) {
  self.host.remove(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rmdir(self, path) {
  self.host.rmdir(path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rename(self, old_path, new_path) {
  self.host.rename(old_path, new_path)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with copy_file(self, src, dst) {
  let data = self.host.read_file(src)
  self.host.write_file(dst, data)
}

///|
pub impl @fs.FileSystemBackend for WasiFs with rm_rf(self, path) {
  rm_rf_host(self.host, path)
}
