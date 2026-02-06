use wasmtime_host_experiments::memfs::*;

#[test]
fn basic_operations() {
    let mut fs = MemFs::new();

    // Create directory
    fs.mkdir("/home").unwrap();
    assert!(fs.is_dir("/home"));

    // Write file
    fs.write_string("/home/test.txt", "Hello").unwrap();
    assert!(fs.is_file("/home/test.txt"));

    // Read file
    let content = fs.read_string("/home/test.txt").unwrap();
    assert_eq!(content, "Hello");

    // Stat
    let stat = fs.stat("/home/test.txt").unwrap();
    assert_eq!(stat.size, 5);
    assert_eq!(stat.file_type, FileType::File);

    // Readdir
    let entries = fs.readdir("/home").unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "test.txt");
}

#[test]
fn path_normalization() {
    assert_eq!(normalize_path("/a/b/c"), "/a/b/c");
    assert_eq!(normalize_path("/a/./b/../c"), "/a/c");
    assert_eq!(normalize_path("//a//b//"), "/a/b");
}

#[test]
fn path_parent() {
    assert_eq!(parent_path("/a/b/c"), "/a/b");
    assert_eq!(parent_path("/a"), "/");
    assert_eq!(parent_path("/"), "/");
}

#[test]
fn path_basename() {
    assert_eq!(basename("/a/b/c"), "c");
    assert_eq!(basename("/a"), "a");
    assert_eq!(basename("/"), "");
}

#[test]
fn mkdir_p() {
    let mut fs = MemFs::new();

    fs.mkdir_p("/a/b/c").unwrap();
    assert!(fs.is_dir("/a"));
    assert!(fs.is_dir("/a/b"));
    assert!(fs.is_dir("/a/b/c"));
}

#[test]
fn remove_and_rmdir() {
    let mut fs = MemFs::new();

    fs.mkdir("/dir").unwrap();
    fs.write_string("/dir/file.txt", "test").unwrap();

    // Remove file
    fs.remove("/dir/file.txt").unwrap();
    assert!(!fs.exists("/dir/file.txt"));

    // Remove empty directory
    fs.rmdir("/dir").unwrap();
    assert!(!fs.exists("/dir"));
}

#[test]
fn copy_file() {
    let mut fs = MemFs::new();

    fs.write_string("/original.txt", "hello world").unwrap();
    fs.copy_file("/original.txt", "/copy.txt").unwrap();

    assert!(fs.exists("/copy.txt"));
    assert_eq!(fs.read_string("/copy.txt").unwrap(), "hello world");
    // Original still exists
    assert!(fs.exists("/original.txt"));
}

#[test]
fn rm_rf() {
    let mut fs = MemFs::new();

    // Create nested structure
    fs.mkdir_p("/a/b/c").unwrap();
    fs.write_string("/a/file1.txt", "1").unwrap();
    fs.write_string("/a/b/file2.txt", "2").unwrap();
    fs.write_string("/a/b/c/file3.txt", "3").unwrap();

    // Remove recursively
    fs.rm_rf("/a").unwrap();

    assert!(!fs.exists("/a"));
    assert!(!fs.exists("/a/b"));
    assert!(!fs.exists("/a/b/c"));
}

#[test]
fn error_not_found() {
    let fs = MemFs::new();
    assert!(matches!(
        fs.read_file("/nonexistent"),
        Err(FsError::NotFound(_))
    ));
}

#[test]
fn error_already_exists() {
    let mut fs = MemFs::new();
    fs.mkdir("/dir").unwrap();
    assert!(matches!(
        fs.mkdir("/dir"),
        Err(FsError::AlreadyExists(_))
    ));
}

#[test]
fn error_not_empty() {
    let mut fs = MemFs::new();
    fs.mkdir("/dir").unwrap();
    fs.write_string("/dir/file.txt", "x").unwrap();
    assert!(matches!(fs.rmdir("/dir"), Err(FsError::NotEmpty(_))));
}

#[test]
fn error_is_a_directory() {
    let mut fs = MemFs::new();
    fs.mkdir("/dir").unwrap();
    assert!(matches!(
        fs.read_file("/dir"),
        Err(FsError::IsADirectory(_))
    ));
    assert!(matches!(
        fs.remove("/dir"),
        Err(FsError::IsADirectory(_))
    ));
}

#[test]
fn overwrite_existing_file() {
    let mut fs = MemFs::new();
    fs.write_string("/file.txt", "old").unwrap();
    fs.write_string("/file.txt", "new").unwrap();
    assert_eq!(fs.read_string("/file.txt").unwrap(), "new");
}

#[test]
fn rename_file() {
    let mut fs = MemFs::new();
    fs.write_string("/old.txt", "content").unwrap();
    fs.rename("/old.txt", "/new.txt").unwrap();
    assert!(!fs.exists("/old.txt"));
    assert_eq!(fs.read_string("/new.txt").unwrap(), "content");
}

#[test]
fn walk_filesystem() {
    let mut fs = MemFs::new();
    fs.mkdir_p("/a/b").unwrap();
    fs.write_string("/a/file1.txt", "hello").unwrap();
    fs.write_string("/a/b/file2.txt", "world").unwrap();

    let mut paths: Vec<(String, bool)> = Vec::new();
    fs.walk(|path, is_dir, _| {
        paths.push((path.to_string(), is_dir));
        Ok(())
    })
    .unwrap();

    assert!(paths.contains(&("/a".to_string(), true)));
    assert!(paths.contains(&("/a/b".to_string(), true)));
    assert!(paths.contains(&("/a/file1.txt".to_string(), false)));
    assert!(paths.contains(&("/a/b/file2.txt".to_string(), false)));
}

#[test]
fn stat_directory() {
    let mut fs = MemFs::new();
    fs.mkdir("/dir").unwrap();
    let stat = fs.stat("/dir").unwrap();
    assert_eq!(stat.file_type, FileType::Directory);
    assert_eq!(stat.size, 0);
}

#[test]
fn root_operations() {
    let fs = MemFs::new();
    assert!(fs.exists("/"));
    assert!(fs.is_dir("/"));
    assert!(!fs.is_file("/"));
    let stat = fs.stat("/").unwrap();
    assert_eq!(stat.file_type, FileType::Directory);
}
