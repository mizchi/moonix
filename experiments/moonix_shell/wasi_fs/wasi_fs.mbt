///| FileSystemBackend implementation over WASI filesystem API

pub struct WasiFs {
  root : @wasi_fs.Descriptor
}

pub fn WasiFs::new(root : @wasi_fs.Descriptor) -> WasiFs {
  { root, }
}

fn no_path_flags() -> @wasi_fs.PathFlags {
  @wasi_fs.PathFlags::from_bits(0)
}

fn string_to_bytes(s : String) -> Array[Byte] {
  let bytes : Array[Byte] = Array::new(capacity=s.length())
  for i in 0..<s.length() {
    bytes.push(s[i].to_int().to_byte())
  }
  bytes
}

fn bytes_to_string(bytes : Array[Byte]) -> String {
  let buf = StringBuilder::new()
  for b in bytes {
    buf.write_char(b.to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn moonbit_bytes_to_array(b : Bytes) -> Array[Byte] {
  let arr : Array[Byte] = Array::new(capacity=b.length())
  for byte in b {
    arr.push(byte)
  }
  arr
}

fn array_to_moonbit_bytes(arr : Array[Byte]) -> Bytes {
  Bytes::makei(arr.length(), fn(i) { arr[i] })
}

fn strip_leading_slash(path : String) -> String {
  if path == "/" {
    "."
  } else if path.has_prefix("/") {
    let buf = StringBuilder::new()
    for i in 1..<path.length() {
      buf.write_char(path[i].to_int().unsafe_to_char())
    }
    buf.to_string()
  } else {
    path
  }
}

fn wasi_error_to_fs(e : @wasi_fs.ErrorCode) -> @fs.FsError {
  match e {
    NoEntry => @fs.FsError::NotFound(e.to_string())
    Exist => @fs.FsError::AlreadyExists(e.to_string())
    NotDirectory => @fs.FsError::NotADirectory(e.to_string())
    IsDirectory => @fs.FsError::IsADirectory(e.to_string())
    NotEmpty => @fs.FsError::NotEmpty(e.to_string())
    _ => @fs.FsError::IoError(e.to_string())
  }
}

fn open_dir_at(
  root : @wasi_fs.Descriptor,
  rel_path : String,
) -> @wasi_fs.Descriptor raise @fs.FsError {
  if rel_path == "." || rel_path.is_empty() {
    return root
  }
  match @wasi_fs.descriptor_open_at(
    root,
    no_path_flags(),
    rel_path,
    @wasi_fs.open_directory,
    @wasi_fs.Read,
  ) {
    Ok(d) => d
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with read_file(self, path) {
  let rel = strip_leading_slash(path)
  let fd = match @wasi_fs.descriptor_open_at(
    self.root,
    no_path_flags(),
    rel,
    @wasi_fs.OpenFlags::from_bits(0),
    @wasi_fs.Read,
  ) {
    Ok(fd) => fd
    Err(e) => raise wasi_error_to_fs(e)
  }
  let (bytes, _eof) = match @wasi_fs.descriptor_read(fd, 1048576UL, 0UL) {
    Ok(result) => result
    Err(e) => raise wasi_error_to_fs(e)
  }
  array_to_moonbit_bytes(bytes)
}

pub impl @fs.FileSystemBackend for WasiFs with read_string(self, path) {
  let data = (self as &@fs.FileSystemBackend).read_file(path)
  let buf = StringBuilder::new()
  for byte in data {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

pub impl @fs.FileSystemBackend for WasiFs with exists(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(_) => true
    Err(_) => false
  }
}

pub impl @fs.FileSystemBackend for WasiFs with is_file(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(stat) => stat.type_ == @wasi_fs.RegularFile
    Err(_) => false
  }
}

pub impl @fs.FileSystemBackend for WasiFs with is_dir(self, path) {
  let rel = strip_leading_slash(path)
  if rel == "." {
    return true
  }
  match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(stat) => stat.type_ == @wasi_fs.Directory
    Err(_) => false
  }
}

pub impl @fs.FileSystemBackend for WasiFs with stat(self, path) {
  let rel = strip_leading_slash(path)
  let s = match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(s) => s
    Err(e) => raise wasi_error_to_fs(e)
  }
  let file_type : @fs.FileType = match s.type_ {
    @wasi_fs.RegularFile => @fs.FileType::File
    @wasi_fs.Directory => @fs.FileType::Directory
    @wasi_fs.SymbolicLink => @fs.FileType::Symlink
    _ => @fs.FileType::File
  }
  { file_type, size: s.size.reinterpret_as_int64().to_int() }
}

pub impl @fs.FileSystemBackend for WasiFs with readdir(self, path) {
  let rel = strip_leading_slash(path)
  let dir_desc = open_dir_at(self.root, rel)
  let dir_stream = match @wasi_fs.descriptor_read_directory(dir_desc) {
    Ok(s) => s
    Err(e) => raise wasi_error_to_fs(e)
  }
  let entries : Array[@fs.DirEntry] = []
  while true {
    match @wasi_fs.directory_entry_stream_read_directory_entry(dir_stream) {
      Ok(Some(entry)) => {
        if entry.name == "." || entry.name == ".." {
          continue
        }
        let file_type : @fs.FileType = match entry.type_ {
          @wasi_fs.RegularFile => @fs.FileType::File
          @wasi_fs.Directory => @fs.FileType::Directory
          @wasi_fs.SymbolicLink => @fs.FileType::Symlink
          _ => @fs.FileType::File
        }
        entries.push({ name: entry.name, file_type })
      }
      Ok(None) => break
      Err(e) => raise wasi_error_to_fs(e)
    }
  }
  entries
}

pub impl @fs.FileSystemBackend for WasiFs with write_file(self, path, data) {
  let rel = strip_leading_slash(path)
  // Ensure parent directory exists
  let parent = @fs.parent_path(path)
  if parent != "/" {
    let parent_rel = strip_leading_slash(parent)
    match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), parent_rel) {
      Ok(_) => ()
      Err(_) => raise @fs.FsError::NotFound("parent directory not found: " + parent)
    }
  }
  let fd = match @wasi_fs.descriptor_open_at(
    self.root,
    no_path_flags(),
    rel,
    @wasi_fs.create,
    @wasi_fs.Write,
  ) {
    Ok(fd) => fd
    Err(e) => raise wasi_error_to_fs(e)
  }
  // Truncate by setting size to 0 first
  match @wasi_fs.descriptor_set_size(fd, 0UL) {
    Ok(_) => ()
    Err(_) => ()
  }
  let arr = moonbit_bytes_to_array(data)
  match @wasi_fs.descriptor_write(fd, arr, 0UL) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with write_string(self, path, content) {
  let data = Bytes::makei(content.length(), fn(i) { content[i].to_int().to_byte() })
  (self as &@fs.FileSystemBackend).write_file(path, data)
}

pub impl @fs.FileSystemBackend for WasiFs with mkdir(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_create_directory_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with mkdir_p(self, path) {
  let normalized = @fs.normalize_path(path)
  if normalized == "/" {
    return
  }
  let parts : Array[String] = []
  for part in normalized.split("/") {
    let s = part.to_string()
    if not(s.is_empty()) {
      parts.push(s)
    }
  }
  let current = StringBuilder::new()
  for part in parts {
    if current.to_string().length() > 0 {
      current.write_char('/')
    }
    current.write_string(part)
    let rel = current.to_string()
    match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
      Ok(stat) =>
        if stat.type_ == @wasi_fs.Directory {
          continue
        } else {
          raise @fs.FsError::NotADirectory(rel)
        }
      Err(_) =>
        match @wasi_fs.descriptor_create_directory_at(self.root, rel) {
          Ok(_) => ()
          Err(e) => raise wasi_error_to_fs(e)
        }
    }
  }
}

pub impl @fs.FileSystemBackend for WasiFs with remove(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_unlink_file_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with rmdir(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_remove_directory_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with rename(self, old_path, new_path) {
  let old_rel = strip_leading_slash(old_path)
  let new_rel = strip_leading_slash(new_path)
  match @wasi_fs.descriptor_rename_at(self.root, old_rel, self.root, new_rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

pub impl @fs.FileSystemBackend for WasiFs with copy_file(self, src, dst) {
  let data = (self as &@fs.FileSystemBackend).read_file(src)
  (self as &@fs.FileSystemBackend).write_file(dst, data)
}

pub impl @fs.FileSystemBackend for WasiFs with rm_rf(self, path) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(stat) =>
      if stat.type_ == @wasi_fs.Directory {
        rm_rf_dir(self.root, path)
      } else {
        match @wasi_fs.descriptor_unlink_file_at(self.root, rel) {
          Ok(_) => ()
          Err(e) => raise wasi_error_to_fs(e)
        }
      }
    Err(_) => () // doesn't exist, nothing to do
  }
}

fn rm_rf_dir(root : @wasi_fs.Descriptor, path : String) -> Unit raise @fs.FsError {
  let rel = strip_leading_slash(path)
  let dir_desc = open_dir_at(root, rel)
  let stream = match @wasi_fs.descriptor_read_directory(dir_desc) {
    Ok(s) => s
    Err(e) => raise wasi_error_to_fs(e)
  }
  let children : Array[(String, @wasi_fs.DescriptorType)] = []
  while true {
    match @wasi_fs.directory_entry_stream_read_directory_entry(stream) {
      Ok(Some(entry)) => {
        if entry.name == "." || entry.name == ".." {
          continue
        }
        children.push((entry.name, entry.type_))
      }
      Ok(None) => break
      Err(e) => raise wasi_error_to_fs(e)
    }
  }
  for child in children {
    let (name, type_) = child
    let child_path = if path == "/" {
      "/" + name
    } else {
      path + "/" + name
    }
    if type_ == @wasi_fs.Directory {
      rm_rf_dir(root, child_path)
    } else {
      let child_rel = strip_leading_slash(child_path)
      match @wasi_fs.descriptor_unlink_file_at(root, child_rel) {
        Ok(_) => ()
        Err(e) => raise wasi_error_to_fs(e)
      }
    }
  }
  match @wasi_fs.descriptor_remove_directory_at(root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}
