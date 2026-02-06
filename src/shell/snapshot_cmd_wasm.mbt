///| snapshot/rollback for wasm targets (in-memory snapshots)

fn join_args(args : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, arg in args {
    if i > 0 {
      buf.write_char(' ')
    }
    buf.write_string(arg)
  }
  buf.to_string()
}

fn is_git_path(path : String) -> Bool {
  path == "/.git" || path.has_prefix("/.git/")
}

fn collect_memfs_files(
  fs : &@fs.FileSystemBackend,
  dir : String,
  out : Array[String],
) -> Unit {
  let entries = fs.readdir(dir) catch {
    _ => return
  }
  for entry in entries {
    let path = if dir == "/" {
      "/" + entry.name
    } else {
      dir + "/" + entry.name
    }
    if is_git_path(path) {
      continue
    }
    match entry.file_type {
      @fs.FileType::Directory => collect_memfs_files(fs, path, out)
      @fs.FileType::File => out.push(path)
      _ => ()
    }
  }
}

fn clear_memfs_root(fs : &@fs.FileSystemBackend) -> Unit {
  let entries = fs.readdir("/") catch {
    _ => return
  }
  for entry in entries {
    let path = "/" + entry.name
    fs.rm_rf(path) catch {
      _ => ()
    }
  }
}

fn snapshot_hash(
  paths : Array[String],
  files : Map[String, Bytes],
) -> @bit.ObjectId {
  let hasher = @bit.Sha1State::new()
  for path in paths {
    hasher.update_string(path)
    hasher.update_byte((0).to_byte())
    match files.get(path) {
      Some(data) => hasher.update(data)
      None => ()
    }
    hasher.update_byte((0).to_byte())
  }
  hasher.finish()
}

pub fn cmd_snapshot(sh : ShellContext, args : Array[String]) -> Int {
  let _ = if args.is_empty() { "snapshot" } else { join_args(args) }

  let paths : Array[String] = []
  collect_memfs_files(sh.fs, "/", paths)
  paths.sort()

  let files : Map[String, Bytes] = {}
  for path in paths {
    let data = sh.fs.read_file(path) catch {
      e => {
        write_stderr(sh.ctx, "snapshot: " + e.to_string() + "\n")
        return 1
      }
    }
    files[path] = data
  }

  let commit_id = snapshot_hash(paths, files)
  let hex = commit_id.to_hex()
  sh.snapshot_store[hex] = files
  sh.snapshot_head = Some(commit_id)
  let _ = sh.next_snapshot_timestamp()

  write_stdout(sh.ctx, hex + "\n")
  0
}

pub fn cmd_rollback(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "rollback: missing commit hash\n")
    return 1
  }
  let hex = args[0]
  let commit_result : Result[@bit.ObjectId, @bit.GitError] =
    try? @bit.ObjectId::from_hex(hex)
  match commit_result {
    Err(e) => {
      write_stderr(sh.ctx, "rollback: " + e.to_string() + "\n")
      1
    }
    Ok(commit_id) =>
      match sh.snapshot_store.get(hex) {
        None => {
          write_stderr(sh.ctx, "rollback: unknown snapshot\n")
          1
        }
        Some(files) => {
          clear_memfs_root(sh.fs)
          for path, data in files {
            let parent = @fs.parent_path(path)
            if parent != "/" {
              sh.fs.mkdir_p(parent) catch {
                _ => ()
              }
            }
            sh.fs.write_file(path, data) catch {
              e => {
                write_stderr(sh.ctx, "rollback: " + e.to_string() + "\n")
                return 1
              }
            }
          }
          sh.snapshot_head = Some(commit_id)
          0
        }
      }
  }
}
