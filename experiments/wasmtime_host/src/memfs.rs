use std::collections::BTreeMap;
use std::fmt;

/// Filesystem error types (mirrors MoonBit FsError).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FsError {
    NotFound(String),
    AlreadyExists(String),
    NotADirectory(String),
    NotAFile(String),
    IsADirectory(String),
    NotEmpty(String),
    PermissionDenied(String),
    InvalidPath(String),
    IoError(String),
}

impl fmt::Display for FsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FsError::NotFound(p) => write!(f, "not found: {p}"),
            FsError::AlreadyExists(p) => write!(f, "already exists: {p}"),
            FsError::NotADirectory(p) => write!(f, "not a directory: {p}"),
            FsError::NotAFile(p) => write!(f, "not a file: {p}"),
            FsError::IsADirectory(p) => write!(f, "is a directory: {p}"),
            FsError::NotEmpty(p) => write!(f, "not empty: {p}"),
            FsError::PermissionDenied(p) => write!(f, "permission denied: {p}"),
            FsError::InvalidPath(p) => write!(f, "invalid path: {p}"),
            FsError::IoError(msg) => write!(f, "io error: {msg}"),
        }
    }
}

impl std::error::Error for FsError {}

/// File type enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileType {
    File,
    Directory,
}

/// File metadata.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileStat {
    pub file_type: FileType,
    pub size: usize,
}

/// Directory entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub file_type: FileType,
}

/// Inode data: either a file with byte content or a directory with named children.
enum InodeData {
    File(Vec<u8>),
    Directory(BTreeMap<String, usize>),
}

/// A single inode in the filesystem.
struct Inode {
    data: InodeData,
}

/// In-memory filesystem (mirrors MoonBit MemFs).
/// Root directory is always inode 0.
pub struct MemFs {
    inodes: Vec<Inode>,
    next_id: usize,
}

// --- Path utilities ---

/// Normalize a path: resolve `.`, `..`, collapse multiple slashes, remove trailing slash.
pub fn normalize_path(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => continue,
            ".." => {
                parts.pop();
            }
            _ => parts.push(part),
        }
    }
    if parts.is_empty() {
        "/".to_string()
    } else {
        format!("/{}", parts.join("/"))
    }
}

/// Get the parent directory of a path.
pub fn parent_path(path: &str) -> String {
    let normalized = normalize_path(path);
    if normalized == "/" {
        return "/".to_string();
    }
    match normalized.rfind('/') {
        Some(0) => "/".to_string(),
        Some(pos) => normalized[..pos].to_string(),
        None => "/".to_string(),
    }
}

/// Get the basename (last component) of a path.
pub fn basename(path: &str) -> String {
    let normalized = normalize_path(path);
    if normalized == "/" {
        return String::new();
    }
    match normalized.rfind('/') {
        Some(pos) => normalized[pos + 1..].to_string(),
        None => normalized,
    }
}

impl MemFs {
    /// Create a new empty filesystem with root directory at inode 0.
    pub fn new() -> Self {
        let mut fs = MemFs {
            inodes: Vec::new(),
            next_id: 0,
        };
        let root_id = fs.alloc_inode(InodeData::Directory(BTreeMap::new()));
        assert_eq!(root_id, 0);
        fs
    }

    fn alloc_inode(&mut self, data: InodeData) -> usize {
        let id = self.next_id;
        self.next_id += 1;
        self.inodes.push(Inode { data });
        id
    }

    fn get_inode(&self, id: usize) -> Option<&Inode> {
        self.inodes.get(id)
    }

    fn get_inode_mut(&mut self, id: usize) -> Option<&mut Inode> {
        self.inodes.get_mut(id)
    }

    /// Resolve a path to its inode id.
    fn resolve(&self, path: &str) -> Option<usize> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Some(0);
        }
        let mut current: usize = 0;
        for part in normalized[1..].split('/') {
            if part.is_empty() {
                continue;
            }
            let inode = self.get_inode(current)?;
            match &inode.data {
                InodeData::Directory(entries) => {
                    current = *entries.get(part)?;
                }
                InodeData::File(_) => return None,
            }
        }
        Some(current)
    }

    // --- Read operations ---

    pub fn read_file(&self, path: &str) -> Result<Vec<u8>, FsError> {
        let id = self.resolve(path).ok_or_else(|| FsError::NotFound(path.to_string()))?;
        let inode = self
            .get_inode(id)
            .ok_or_else(|| FsError::NotFound(path.to_string()))?;
        match &inode.data {
            InodeData::File(data) => Ok(data.clone()),
            InodeData::Directory(_) => Err(FsError::IsADirectory(path.to_string())),
        }
    }

    pub fn read_string(&self, path: &str) -> Result<String, FsError> {
        let bytes = self.read_file(path)?;
        String::from_utf8(bytes).map_err(|_| FsError::IoError("invalid utf-8".to_string()))
    }

    pub fn exists(&self, path: &str) -> bool {
        self.resolve(path).is_some()
    }

    pub fn is_file(&self, path: &str) -> bool {
        self.resolve(path)
            .and_then(|id| self.get_inode(id))
            .map(|inode| matches!(&inode.data, InodeData::File(_)))
            .unwrap_or(false)
    }

    pub fn is_dir(&self, path: &str) -> bool {
        self.resolve(path)
            .and_then(|id| self.get_inode(id))
            .map(|inode| matches!(&inode.data, InodeData::Directory(_)))
            .unwrap_or(false)
    }

    pub fn stat(&self, path: &str) -> Result<FileStat, FsError> {
        let id = self.resolve(path).ok_or_else(|| FsError::NotFound(path.to_string()))?;
        let inode = self
            .get_inode(id)
            .ok_or_else(|| FsError::NotFound(path.to_string()))?;
        match &inode.data {
            InodeData::File(data) => Ok(FileStat {
                file_type: FileType::File,
                size: data.len(),
            }),
            InodeData::Directory(_) => Ok(FileStat {
                file_type: FileType::Directory,
                size: 0,
            }),
        }
    }

    pub fn readdir(&self, path: &str) -> Result<Vec<DirEntry>, FsError> {
        let id = self.resolve(path).ok_or_else(|| FsError::NotFound(path.to_string()))?;
        let inode = self
            .get_inode(id)
            .ok_or_else(|| FsError::NotFound(path.to_string()))?;
        match &inode.data {
            InodeData::Directory(entries) => {
                let mut result = Vec::new();
                for (name, child_id) in entries {
                    if let Some(child) = self.get_inode(*child_id) {
                        let file_type = match &child.data {
                            InodeData::File(_) => FileType::File,
                            InodeData::Directory(_) => FileType::Directory,
                        };
                        result.push(DirEntry {
                            name: name.clone(),
                            file_type,
                        });
                    }
                }
                Ok(result)
            }
            InodeData::File(_) => Err(FsError::NotADirectory(path.to_string())),
        }
    }

    // --- Write operations ---

    pub fn write_file(&mut self, path: &str, data: Vec<u8>) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        let parent = parent_path(&normalized);
        let name = basename(&normalized);

        let parent_id = self
            .resolve(&parent)
            .ok_or_else(|| FsError::NotFound(parent.clone()))?;

        // Check if file already exists
        let existing_id = {
            let parent_inode = self
                .get_inode(parent_id)
                .ok_or_else(|| FsError::NotFound(parent.clone()))?;
            match &parent_inode.data {
                InodeData::File(_) => return Err(FsError::NotADirectory(parent)),
                InodeData::Directory(entries) => entries.get(&name).copied(),
            }
        };

        match existing_id {
            Some(id) => {
                let inode = self
                    .get_inode_mut(id)
                    .ok_or_else(|| FsError::IoError("corrupted inode".to_string()))?;
                match &inode.data {
                    InodeData::File(_) => {
                        inode.data = InodeData::File(data);
                        Ok(())
                    }
                    InodeData::Directory(_) => Err(FsError::IsADirectory(normalized)),
                }
            }
            None => {
                let new_id = self.alloc_inode(InodeData::File(data));
                let parent_inode = self
                    .get_inode_mut(parent_id)
                    .ok_or_else(|| FsError::IoError("corrupted inode".to_string()))?;
                match &mut parent_inode.data {
                    InodeData::Directory(entries) => {
                        entries.insert(name, new_id);
                        Ok(())
                    }
                    InodeData::File(_) => Err(FsError::NotADirectory(parent)),
                }
            }
        }
    }

    pub fn write_string(&mut self, path: &str, content: &str) -> Result<(), FsError> {
        self.write_file(path, content.as_bytes().to_vec())
    }

    pub fn mkdir(&mut self, path: &str) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Err(FsError::AlreadyExists(path.to_string()));
        }

        let parent = parent_path(&normalized);
        let name = basename(&normalized);

        let parent_id = self
            .resolve(&parent)
            .ok_or_else(|| FsError::NotFound(parent.clone()))?;

        // Check for existing entry
        {
            let parent_inode = self
                .get_inode(parent_id)
                .ok_or_else(|| FsError::NotFound(parent.clone()))?;
            match &parent_inode.data {
                InodeData::File(_) => return Err(FsError::NotADirectory(parent)),
                InodeData::Directory(entries) => {
                    if entries.contains_key(&name) {
                        return Err(FsError::AlreadyExists(path.to_string()));
                    }
                }
            }
        }

        let new_id = self.alloc_inode(InodeData::Directory(BTreeMap::new()));
        let parent_inode = self
            .get_inode_mut(parent_id)
            .ok_or_else(|| FsError::IoError("corrupted inode".to_string()))?;
        match &mut parent_inode.data {
            InodeData::Directory(entries) => {
                entries.insert(name, new_id);
                Ok(())
            }
            InodeData::File(_) => Err(FsError::NotADirectory(parent)),
        }
    }

    pub fn mkdir_p(&mut self, path: &str) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Ok(());
        }

        let parts: Vec<&str> = normalized[1..].split('/').collect();
        let mut current_path = String::new();

        for part in parts {
            current_path.push('/');
            current_path.push_str(part);
            if !self.exists(&current_path) {
                self.mkdir(&current_path)?;
            } else if !self.is_dir(&current_path) {
                return Err(FsError::NotADirectory(current_path));
            }
        }
        Ok(())
    }

    pub fn remove(&mut self, path: &str) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Err(FsError::PermissionDenied("cannot remove root".to_string()));
        }

        let parent = parent_path(&normalized);
        let name = basename(&normalized);

        let parent_id = self
            .resolve(&parent)
            .ok_or_else(|| FsError::NotFound(parent.clone()))?;

        // Verify the target is a file
        let target_id = {
            let parent_inode = self
                .get_inode(parent_id)
                .ok_or_else(|| FsError::NotFound(parent.clone()))?;
            match &parent_inode.data {
                InodeData::File(_) => return Err(FsError::NotADirectory(parent)),
                InodeData::Directory(entries) => {
                    *entries
                        .get(&name)
                        .ok_or_else(|| FsError::NotFound(path.to_string()))?
                }
            }
        };

        {
            let target_inode = self
                .get_inode(target_id)
                .ok_or_else(|| FsError::NotFound(path.to_string()))?;
            match &target_inode.data {
                InodeData::File(_) => {}
                InodeData::Directory(_) => return Err(FsError::IsADirectory(path.to_string())),
            }
        }

        let parent_inode = self
            .get_inode_mut(parent_id)
            .ok_or_else(|| FsError::IoError("corrupted inode".to_string()))?;
        if let InodeData::Directory(entries) = &mut parent_inode.data {
            entries.remove(&name);
        }
        Ok(())
    }

    pub fn rmdir(&mut self, path: &str) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Err(FsError::PermissionDenied("cannot remove root".to_string()));
        }

        let parent = parent_path(&normalized);
        let name = basename(&normalized);

        let parent_id = self
            .resolve(&parent)
            .ok_or_else(|| FsError::NotFound(parent.clone()))?;

        // Verify the target is an empty directory
        let target_id = {
            let parent_inode = self
                .get_inode(parent_id)
                .ok_or_else(|| FsError::NotFound(parent.clone()))?;
            match &parent_inode.data {
                InodeData::File(_) => return Err(FsError::NotADirectory(parent)),
                InodeData::Directory(entries) => {
                    *entries
                        .get(&name)
                        .ok_or_else(|| FsError::NotFound(path.to_string()))?
                }
            }
        };

        {
            let target_inode = self
                .get_inode(target_id)
                .ok_or_else(|| FsError::NotFound(path.to_string()))?;
            match &target_inode.data {
                InodeData::File(_) => return Err(FsError::NotAFile(path.to_string())),
                InodeData::Directory(children) => {
                    if !children.is_empty() {
                        return Err(FsError::NotEmpty(path.to_string()));
                    }
                }
            }
        }

        let parent_inode = self
            .get_inode_mut(parent_id)
            .ok_or_else(|| FsError::IoError("corrupted inode".to_string()))?;
        if let InodeData::Directory(entries) = &mut parent_inode.data {
            entries.remove(&name);
        }
        Ok(())
    }

    pub fn rename(&mut self, old_path: &str, new_path: &str) -> Result<(), FsError> {
        let old_normalized = normalize_path(old_path);
        let new_normalized = normalize_path(new_path);

        if old_normalized == new_normalized {
            return Ok(());
        }

        if self.is_file(&old_normalized) {
            let data = self.read_file(&old_normalized)?;
            self.write_file(&new_normalized, data)?;
            self.remove(&old_normalized)?;
            Ok(())
        } else if self.is_dir(&old_normalized) {
            Err(FsError::IoError(
                "directory rename not yet implemented".to_string(),
            ))
        } else {
            Err(FsError::NotFound(old_path.to_string()))
        }
    }

    pub fn copy_file(&mut self, src: &str, dst: &str) -> Result<(), FsError> {
        let src_normalized = normalize_path(src);
        let dst_normalized = normalize_path(dst);

        if self.is_dir(&src_normalized) {
            return Err(FsError::IsADirectory(src.to_string()));
        }
        if !self.is_file(&src_normalized) {
            return Err(FsError::NotFound(src.to_string()));
        }

        let data = self.read_file(&src_normalized)?;
        self.write_file(&dst_normalized, data)
    }

    pub fn rm_rf(&mut self, path: &str) -> Result<(), FsError> {
        let normalized = normalize_path(path);
        if normalized == "/" {
            return Err(FsError::PermissionDenied("cannot remove root".to_string()));
        }

        if !self.exists(&normalized) {
            return Err(FsError::NotFound(path.to_string()));
        }

        if self.is_file(&normalized) {
            return self.remove(&normalized);
        }

        // Directory: recursively delete contents
        let entries = self.readdir(&normalized)?;
        for entry in entries {
            let child_path = format!("{}/{}", normalized, entry.name);
            self.rm_rf(&child_path)?;
        }
        self.rmdir(&normalized)
    }

    /// Walk the entire filesystem tree, calling the visitor with (path, is_dir, content).
    /// Used by FsBridge::materialize.
    pub fn walk<F>(&self, mut visitor: F) -> Result<(), FsError>
    where
        F: FnMut(&str, bool, Option<&[u8]>) -> Result<(), FsError>,
    {
        self.walk_recursive("/", &mut visitor)
    }

    fn walk_recursive<F>(&self, path: &str, visitor: &mut F) -> Result<(), FsError>
    where
        F: FnMut(&str, bool, Option<&[u8]>) -> Result<(), FsError>,
    {
        let id = self.resolve(path).ok_or_else(|| FsError::NotFound(path.to_string()))?;
        let inode = self
            .get_inode(id)
            .ok_or_else(|| FsError::NotFound(path.to_string()))?;

        match &inode.data {
            InodeData::File(data) => {
                visitor(path, false, Some(data))?;
            }
            InodeData::Directory(entries) => {
                if path != "/" {
                    visitor(path, true, None)?;
                }
                // Collect keys to avoid borrow issues
                let names: Vec<String> = entries.keys().cloned().collect();
                for name in names {
                    let child_path = if path == "/" {
                        format!("/{name}")
                    } else {
                        format!("{path}/{name}")
                    };
                    self.walk_recursive(&child_path, visitor)?;
                }
            }
        }
        Ok(())
    }
}
