use crate::memfs::{FsError, MemFs};
use std::path::PathBuf;
use tempfile::TempDir;

/// Bridge between MemFs and a real tempdir for WASI host preopened directories.
pub struct FsBridge {
    memfs: MemFs,
    tempdir: Option<TempDir>,
}

impl FsBridge {
    pub fn new(memfs: MemFs) -> Self {
        FsBridge {
            memfs,
            tempdir: None,
        }
    }

    /// Materialize the MemFs contents into a real tempdir.
    /// Returns the path to the tempdir root.
    pub fn materialize(&mut self) -> Result<PathBuf, FsError> {
        let tempdir = TempDir::new().map_err(|e| FsError::IoError(e.to_string()))?;
        let root = tempdir.path().to_path_buf();

        self.memfs.walk(|path, is_dir, content| {
            let real_path = root.join(&path[1..]); // strip leading '/'
            if is_dir {
                std::fs::create_dir_all(&real_path)
                    .map_err(|e| FsError::IoError(e.to_string()))?;
            } else if let Some(data) = content {
                if let Some(parent) = real_path.parent() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| FsError::IoError(e.to_string()))?;
                }
                std::fs::write(&real_path, data).map_err(|e| FsError::IoError(e.to_string()))?;
            }
            Ok(())
        })?;

        self.tempdir = Some(tempdir);
        Ok(root)
    }

    /// Snapshot the tempdir contents back into MemFs.
    /// Replaces the current MemFs with a fresh one built from the tempdir.
    pub fn snapshot(&mut self) -> Result<(), FsError> {
        let tempdir = self
            .tempdir
            .as_ref()
            .ok_or_else(|| FsError::IoError("no tempdir materialized".to_string()))?;
        let root = tempdir.path();

        let mut new_fs = MemFs::new();
        Self::snapshot_recursive(root, "/", &mut new_fs)?;
        self.memfs = new_fs;
        Ok(())
    }

    fn snapshot_recursive(
        real_path: &std::path::Path,
        virtual_path: &str,
        fs: &mut MemFs,
    ) -> Result<(), FsError> {
        let entries =
            std::fs::read_dir(real_path).map_err(|e| FsError::IoError(e.to_string()))?;

        for entry in entries {
            let entry = entry.map_err(|e| FsError::IoError(e.to_string()))?;
            let name = entry
                .file_name()
                .to_str()
                .ok_or_else(|| FsError::IoError("invalid filename".to_string()))?
                .to_string();
            let child_virtual = if virtual_path == "/" {
                format!("/{name}")
            } else {
                format!("{virtual_path}/{name}")
            };
            let file_type = entry
                .file_type()
                .map_err(|e| FsError::IoError(e.to_string()))?;

            if file_type.is_dir() {
                fs.mkdir(&child_virtual)?;
                Self::snapshot_recursive(&entry.path(), &child_virtual, fs)?;
            } else if file_type.is_file() {
                let data =
                    std::fs::read(entry.path()).map_err(|e| FsError::IoError(e.to_string()))?;
                fs.write_file(&child_virtual, data)?;
            }
        }
        Ok(())
    }

    /// Consume the bridge and return the MemFs.
    pub fn into_memfs(self) -> MemFs {
        self.memfs
    }

    /// Get a reference to the MemFs.
    pub fn memfs(&self) -> &MemFs {
        &self.memfs
    }

    /// Get the tempdir path (if materialized).
    pub fn tempdir_path(&self) -> Option<&std::path::Path> {
        self.tempdir.as_ref().map(|t| t.path())
    }
}
