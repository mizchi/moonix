use wasmtime_host_experiments::fs_bridge::FsBridge;
use wasmtime_host_experiments::memfs::MemFs;

#[test]
fn materialize_empty_fs() {
    let fs = MemFs::new();
    let mut bridge = FsBridge::new(fs);
    let path = bridge.materialize().unwrap();
    assert!(path.exists());
    assert!(path.is_dir());
}

#[test]
fn materialize_files_and_dirs() {
    let mut fs = MemFs::new();
    fs.mkdir("/src").unwrap();
    fs.write_string("/src/main.rs", "fn main() {}").unwrap();
    fs.mkdir_p("/src/lib").unwrap();
    fs.write_string("/src/lib/mod.rs", "pub mod foo;").unwrap();

    let mut bridge = FsBridge::new(fs);
    let root = bridge.materialize().unwrap();

    assert!(root.join("src").is_dir());
    assert!(root.join("src/main.rs").is_file());
    assert!(root.join("src/lib").is_dir());
    assert!(root.join("src/lib/mod.rs").is_file());

    let content = std::fs::read_to_string(root.join("src/main.rs")).unwrap();
    assert_eq!(content, "fn main() {}");

    let content = std::fs::read_to_string(root.join("src/lib/mod.rs")).unwrap();
    assert_eq!(content, "pub mod foo;");
}

#[test]
fn roundtrip_preserves_content() {
    let mut fs = MemFs::new();
    fs.mkdir_p("/a/b").unwrap();
    fs.write_string("/a/file.txt", "hello").unwrap();
    fs.write_string("/a/b/data.bin", "world").unwrap();

    let mut bridge = FsBridge::new(fs);
    bridge.materialize().unwrap();
    bridge.snapshot().unwrap();

    let fs = bridge.into_memfs();
    assert!(fs.is_dir("/a"));
    assert!(fs.is_dir("/a/b"));
    assert_eq!(fs.read_string("/a/file.txt").unwrap(), "hello");
    assert_eq!(fs.read_string("/a/b/data.bin").unwrap(), "world");
}

#[test]
fn snapshot_captures_changes() {
    let mut fs = MemFs::new();
    fs.write_string("/file.txt", "original").unwrap();

    let mut bridge = FsBridge::new(fs);
    let root = bridge.materialize().unwrap();

    // Modify file on disk
    std::fs::write(root.join("file.txt"), "modified").unwrap();

    bridge.snapshot().unwrap();
    let fs = bridge.into_memfs();
    assert_eq!(fs.read_string("/file.txt").unwrap(), "modified");
}

#[test]
fn snapshot_captures_new_files() {
    let mut fs = MemFs::new();
    fs.mkdir("/dir").unwrap();

    let mut bridge = FsBridge::new(fs);
    let root = bridge.materialize().unwrap();

    // Create new file on disk
    std::fs::write(root.join("dir/new.txt"), "new content").unwrap();

    bridge.snapshot().unwrap();
    let fs = bridge.into_memfs();
    assert!(fs.exists("/dir/new.txt"));
    assert_eq!(fs.read_string("/dir/new.txt").unwrap(), "new content");
}

#[test]
fn snapshot_captures_deletions() {
    let mut fs = MemFs::new();
    fs.write_string("/keep.txt", "keep").unwrap();
    fs.write_string("/delete.txt", "delete").unwrap();

    let mut bridge = FsBridge::new(fs);
    let root = bridge.materialize().unwrap();

    // Delete file on disk
    std::fs::remove_file(root.join("delete.txt")).unwrap();

    bridge.snapshot().unwrap();
    let fs = bridge.into_memfs();
    assert!(fs.exists("/keep.txt"));
    assert!(!fs.exists("/delete.txt"));
}

#[test]
fn tempdir_path_before_materialize() {
    let fs = MemFs::new();
    let bridge = FsBridge::new(fs);
    assert!(bridge.tempdir_path().is_none());
}

#[test]
fn tempdir_path_after_materialize() {
    let fs = MemFs::new();
    let mut bridge = FsBridge::new(fs);
    let path = bridge.materialize().unwrap();
    assert_eq!(bridge.tempdir_path().unwrap(), path);
}
