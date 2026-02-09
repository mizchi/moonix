///|
pub struct FsAdapter {
  kernel : Kernel
  mut current_descriptor : Int
  mut current_dir_stream : Int
}

///|
pub fn FsAdapter::new(kernel : Kernel) -> FsAdapter {
  { kernel, current_descriptor: 0, current_dir_stream: 0 }
}

///|
pub fn FsAdapter::set_descriptor(self : FsAdapter, id : Int) -> Unit {
  self.current_descriptor = id
}

///|
pub fn FsAdapter::set_dir_stream(self : FsAdapter, id : Int) -> Unit {
  self.current_dir_stream = id
}

///|
fn FsAdapter::get_desc_path(self : FsAdapter) -> Result[String, @p2.WasiError] {
  match self.kernel.descriptors.get(self.current_descriptor) {
    Some(desc) => Ok(desc.path)
    None =>
      Err(
        @p2.WasiError::FromFilesystemtypeserrorcode(
          @p2.FilesystemTypesErrorCode::BadDescriptor,
        ),
      )
  }
}

///|
fn resolve_child_path(base : String, child : String) -> String {
  if child.has_prefix("/") {
    @fs.normalize_path(child)
  } else {
    @fs.normalize_path(base + "/" + child)
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_read_via_stream(
  self,
  offset,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(_) => {
      let stream_id = self.kernel.alloc_stream(
        FileRead(self.current_descriptor, offset.0),
      )
      Ok(@p2.FilesystemTypesInputStream(stream_id))
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_write_via_stream(
  self,
  offset,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(_) => {
      let stream_id = self.kernel.alloc_stream(
        FileWrite(self.current_descriptor, offset.0),
      )
      Ok(@p2.FilesystemTypesOutputStream(stream_id))
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_append_via_stream(
  self,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(_) => {
      let stream_id = self.kernel.alloc_stream(
        FileAppend(self.current_descriptor),
      )
      Ok(@p2.FilesystemTypesOutputStream(stream_id))
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_advise(
  _self,
  _offset,
  _len,
  _advice,
) {
  Ok(())
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_sync_data(
  _self,
) {
  Ok(())
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_get_flags(
  _self,
) {
  // Read+Write flags
  Ok(@p2.FilesystemTypesDescriptorFlags(3))
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_get_type(
  self,
) {
  match self.kernel.descriptors.get(self.current_descriptor) {
    Some(desc) => Ok(desc.type_)
    None =>
      Err(
        @p2.WasiError::FromFilesystemtypeserrorcode(
          @p2.FilesystemTypesErrorCode::BadDescriptor,
        ),
      )
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_set_size(
  self,
  size,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(path) =>
      try {
        let existing = if self.kernel.fs.exists(path) &&
          self.kernel.fs.is_file(path) {
          self.kernel.fs.read_file(path)
        } else {
          b""
        }
        let new_len = size.0.to_int()
        if new_len <= existing.length() {
          // Truncate
          let result : Array[Byte] = []
          for i = 0; i < new_len; i = i + 1 {
            result.push(existing[i])
          }
          self.kernel.fs.write_file(path, Bytes::from_iter(result.iter()))
        } else {
          // Extend with zeroes
          let result : Array[Byte] = []
          for b in existing {
            result.push(b)
          }
          for _i = existing.length(); _i < new_len; _i = _i + 1 {
            result.push(b'\x00')
          }
          self.kernel.fs.write_file(path, Bytes::from_iter(result.iter()))
        }
        Ok(())
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_set_times(
  _self,
  _atime,
  _mtime,
) {
  Ok(())
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_read(
  self,
  len,
  offset,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(path) =>
      try {
        let data = self.kernel.fs.read_file(path)
        let start = offset.0.to_int()
        if start >= data.length() {
          return Ok(b"")
        }
        let avail = data.length() - start
        let to_read = if len.0.to_int() < avail {
          len.0.to_int()
        } else {
          avail
        }
        let result : Array[Byte] = []
        for i = 0; i < to_read; i = i + 1 {
          result.push(data[start + i])
        }
        Ok(Bytes::from_iter(result.iter()))
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_write(
  self,
  data,
  offset,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(path) =>
      try {
        let existing = if self.kernel.fs.exists(path) &&
          self.kernel.fs.is_file(path) {
          self.kernel.fs.read_file(path)
        } else {
          b""
        }
        let start = offset.0.to_int()
        let new_len = if start + data.length() > existing.length() {
          start + data.length()
        } else {
          existing.length()
        }
        let result : Array[Byte] = []
        for i = 0; i < new_len; i = i + 1 {
          if i >= start && i < start + data.length() {
            result.push(data[i - start])
          } else if i < existing.length() {
            result.push(existing[i])
          } else {
            result.push(b'\x00')
          }
        }
        self.kernel.fs.write_file(path, Bytes::from_iter(result.iter()))
        Ok(@p2.FilesystemTypesFilesize(data.length().to_uint64()))
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_read_directory(
  self,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(path) =>
      try {
        let entries_raw = self.kernel.fs.readdir(path)
        let entries : Array[@p2.FilesystemTypesDirectoryEntry] = []
        for entry in entries_raw {
          entries.push(@p2.FilesystemTypesDirectoryEntry::{ name: entry.name })
        }
        let ds_id = self.kernel.alloc_dir_stream(DirStreamState::{
          entries,
          cursor: 0,
        })
        Ok(@p2.FilesystemTypesDirectoryEntryStream(ds_id))
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_sync(
  _self,
) {
  Ok(())
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_create_directory_at(
  self,
  name,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let target = resolve_child_path(base, name)
      try {
        self.kernel.fs.mkdir(target)
        Ok(())
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
    }
  }
}

///|
fn make_stat(s : @fs.FileStat) -> @p2.FilesystemTypesDescriptorStat {
  {
    link_count: @p2.FilesystemTypesLinkCount(1UL),
    size: @p2.FilesystemTypesFilesize(s.size.to_uint64()),
    data_access_timestamp: None,
    data_modification_timestamp: None,
    status_change_timestamp: None,
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_stat(self) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(path) =>
      try {
        let s = self.kernel.fs.stat(path)
        Ok(make_stat(s))
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_stat_at(
  self,
  _flags,
  child_path,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let target = resolve_child_path(base, child_path)
      try {
        let s = self.kernel.fs.stat(target)
        Ok(make_stat(s))
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_set_times_at(
  _self,
  _flags,
  _path,
  _atime,
  _mtime,
) {
  Ok(())
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_link_at(
  _self,
  _flags,
  _old_path,
  _new_descriptor,
  _new_path,
) {
  Err(
    @p2.WasiError::FromFilesystemtypeserrorcode(
      @p2.FilesystemTypesErrorCode::Unsupported,
    ),
  )
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_readlink_at(
  _self,
  _path,
) {
  Err(
    @p2.WasiError::FromFilesystemtypeserrorcode(
      @p2.FilesystemTypesErrorCode::Unsupported,
    ),
  )
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_remove_directory_at(
  self,
  name,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let target = resolve_child_path(base, name)
      try {
        self.kernel.fs.rmdir(target)
        Ok(())
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_rename_at(
  self,
  old_name,
  _new_descriptor,
  new_name,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let old_path = resolve_child_path(base, old_name)
      let new_path = resolve_child_path(base, new_name)
      try {
        self.kernel.fs.rename(old_path, new_path)
        Ok(())
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_symlink_at(
  _self,
  _old_path,
  _new_path,
) {
  Err(
    @p2.WasiError::FromFilesystemtypeserrorcode(
      @p2.FilesystemTypesErrorCode::Unsupported,
    ),
  )
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_unlink_file_at(
  self,
  name,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let target = resolve_child_path(base, name)
      try {
        self.kernel.fs.remove(target)
        Ok(())
      } catch {
        e => Err(fs_error_to_wasi(e))
      }
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_is_same_object(
  self,
  other,
) {
  Ok(self.current_descriptor == other.0)
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_metadata_hash(
  self,
) {
  Ok(@p2.FilesystemTypesMetadataHashValue::{
    lower: self.current_descriptor.to_uint64(),
    upper: 0UL,
  })
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with descriptor_metadata_hash_at(
  self,
  _flags,
  child_path,
) {
  match self.get_desc_path() {
    Err(e) => Err(e)
    Ok(base) => {
      let target = resolve_child_path(base, child_path)
      // Use a simple hash of the path
      let mut h = 0UL
      for i = 0; i < target.length(); i = i + 1 {
        h = h * 31UL + target[i].to_int().to_uint64()
      }
      Ok(@p2.FilesystemTypesMetadataHashValue::{ lower: h, upper: 0UL })
    }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with directory_entry_stream_read_directory_entry(
  self,
) {
  let ds_id = self.current_dir_stream
  match self.kernel.dir_streams.get(ds_id) {
    None =>
      Err(
        @p2.WasiError::FromFilesystemtypeserrorcode(
          @p2.FilesystemTypesErrorCode::BadDescriptor,
        ),
      )
    Some(ds) =>
      if ds.cursor >= ds.entries.length() {
        Ok(None)
      } else {
        let entry = ds.entries[ds.cursor]
        ds.cursor += 1
        Ok(Some(entry))
      }
  }
}

///|
pub impl @p2.WasiFilesystemTypesAdapter for FsAdapter with filesystem_error_code(
  _self,
  _err,
) {
  Ok(None)
}

///|
pub impl @p2.WasiFilesystemPreopensAdapter for FsAdapter with get_directories(
  self,
) {
  let result : Array[Bytes] = []
  for i, path in self.kernel.preopens {
    // Encode as descriptor_id (4 bytes LE) + path bytes
    let path_bytes : Array[Byte] = []
    path_bytes.push((i & 0xFF).to_byte())
    path_bytes.push(((i >> 8) & 0xFF).to_byte())
    path_bytes.push(((i >> 16) & 0xFF).to_byte())
    path_bytes.push(((i >> 24) & 0xFF).to_byte())
    for j = 0; j < path.length(); j = j + 1 {
      path_bytes.push(path[j].to_int().to_byte())
    }
    result.push(Bytes::from_iter(path_bytes.iter()))
  }
  Ok(result)
}
