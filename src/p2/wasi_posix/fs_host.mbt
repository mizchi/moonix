///|
/// WASI Preview2 implementation of `WasiFsHost`.
pub struct WasiPreview2FsHost {
  root : @wasi_fs.Descriptor
}

///|
pub fn WasiPreview2FsHost::new(
  root : @wasi_fs.Descriptor,
) -> WasiPreview2FsHost {
  { root, }
}

///|
fn no_path_flags() -> @wasi_fs.PathFlags {
  @wasi_fs.PathFlags::from_bits(0)
}

///|
fn moonbit_bytes_to_array(b : Bytes) -> Array[Byte] {
  let arr : Array[Byte] = Array::new(capacity=b.length())
  for byte in b {
    arr.push(byte)
  }
  arr
}

///|
fn array_to_moonbit_bytes(arr : Array[Byte]) -> Bytes {
  Bytes::makei(arr.length(), fn(i) { arr[i] })
}

///|
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

///|
fn descriptor_type_to_node_type(
  t : @wasi_fs.DescriptorType,
) -> @wasi_posix_core.WasiNodeType {
  match t {
    @wasi_fs.RegularFile => @wasi_posix_core.WasiNodeType::File
    @wasi_fs.Directory => @wasi_posix_core.WasiNodeType::Directory
    @wasi_fs.SymbolicLink => @wasi_posix_core.WasiNodeType::Symlink
    _ => @wasi_posix_core.WasiNodeType::Other
  }
}

///|
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

///|
fn open_dir_at(
  root : @wasi_fs.Descriptor,
  rel_path : String,
) -> @wasi_fs.Descriptor raise @fs.FsError {
  if rel_path == "." || rel_path.is_empty() {
    return root
  }
  match
    @wasi_fs.descriptor_open_at(
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

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with read_file(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  let fd = match
    @wasi_fs.descriptor_open_at(
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

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with exists(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with stat(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  let s = match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), rel) {
    Ok(s) => s
    Err(e) => raise wasi_error_to_fs(e)
  }
  {
    node_type: descriptor_type_to_node_type(s.type_),
    size: s.size.reinterpret_as_int64().to_int(),
  }
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with readdir(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  let dir_desc = open_dir_at(self.root, rel)
  let dir_stream = match @wasi_fs.descriptor_read_directory(dir_desc) {
    Ok(s) => s
    Err(e) => raise wasi_error_to_fs(e)
  }
  let entries : Array[@wasi_posix_core.WasiDirEntry] = []
  while true {
    match @wasi_fs.directory_entry_stream_read_directory_entry(dir_stream) {
      Ok(Some(entry)) => {
        if entry.name == "." || entry.name == ".." {
          continue
        }
        entries.push({
          name: entry.name,
          node_type: descriptor_type_to_node_type(entry.type_),
        })
      }
      Ok(None) => break
      Err(e) => raise wasi_error_to_fs(e)
    }
  }
  entries
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with write_file(
  self,
  path,
  data,
) {
  let rel = strip_leading_slash(path)
  let parent = @fs.parent_path(path)
  if parent != "/" {
    let parent_rel = strip_leading_slash(parent)
    match @wasi_fs.descriptor_stat_at(self.root, no_path_flags(), parent_rel) {
      Ok(_) => ()
      Err(_) =>
        raise @fs.FsError::NotFound("parent directory not found: " + parent)
    }
  }
  let fd = match
    @wasi_fs.descriptor_open_at(
      self.root,
      no_path_flags(),
      rel,
      @wasi_fs.create,
      @wasi_fs.Write,
    ) {
    Ok(fd) => fd
    Err(e) => raise wasi_error_to_fs(e)
  }
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

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with mkdir(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_create_directory_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with mkdir_p(
  self,
  path,
) {
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

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with remove(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_unlink_file_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with rmdir(
  self,
  path,
) {
  let rel = strip_leading_slash(path)
  match @wasi_fs.descriptor_remove_directory_at(self.root, rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}

///|
pub impl @wasi_posix_core.WasiFsHost for WasiPreview2FsHost with rename(
  self,
  old_path,
  new_path,
) {
  let old_rel = strip_leading_slash(old_path)
  let new_rel = strip_leading_slash(new_path)
  match @wasi_fs.descriptor_rename_at(self.root, old_rel, self.root, new_rel) {
    Ok(_) => ()
    Err(e) => raise wasi_error_to_fs(e)
  }
}
