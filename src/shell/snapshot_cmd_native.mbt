///| snapshot/rollup commands backed by mizchi/bit/x/fs

fn git_dir_path() -> String {
  "/.git"
}

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

fn to_rel_path(path : String) -> String {
  let normalized = @fs.normalize_path(path)
  if normalized == "/" {
    ""
  } else if normalized.has_prefix("/") {
    String::unsafe_substring(normalized, start=1, end=normalized.length())
  } else {
    normalized
  }
}

fn is_git_path(path : String) -> Bool {
  path == "/.git" || path.has_prefix("/.git/")
}

fn collect_memfs_files(
  fs : @fs.MemFs,
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

fn clear_memfs_root(fs : @fs.MemFs) -> Unit {
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

fn build_bitfs_from_memfs(sh : ShellContext) -> @bitfs.Fs raise @bit.GitError {
  let config = @bitfs.FsConfig::local_only()
  let git_dir = git_dir_path()
  let bit_fs = match sh.snapshot_head {
    Some(id) => @bitfs.Fs::from_commit(sh.git_store, git_dir, id, config=config)
    None => @bitfs.Fs::empty(git_dir, config=config)
  }

  let mem_files : Array[String] = []
  collect_memfs_files(sh.fs, "/", mem_files)

  let mem_set : Map[String, Bool] = {}
  for path in mem_files {
    let rel = to_rel_path(path)
    mem_set[rel] = true
    let data = sh.fs.read_file(path) catch {
      e => raise @bit.GitError::IoError(e.to_string())
    }
    bit_fs.write_file(rel, data)
  }

  match sh.snapshot_head {
    Some(base_id) => {
      let base_fs = @bitfs.Fs::from_commit(
        sh.git_store,
        git_dir,
        base_id,
        config=config,
      )
      let base_files = base_fs.collect_files_bfs(sh.git_store, 1_000_000)
      for base_path in base_files {
        if not(mem_set.contains(base_path)) {
          bit_fs.remove_file(base_path)
        }
      }
    }
    None => ()
  }

  bit_fs
}

fn apply_bitfs_to_memfs(sh : ShellContext, bit_fs : @bitfs.Fs) -> Unit raise @bit.GitError {
  clear_memfs_root(sh.fs)
  let files = bit_fs.collect_files_bfs(sh.git_store, 1_000_000)
  for file_path in files {
    let data = bit_fs.read_file(sh.git_store, file_path)
    let abs_path = "/" + file_path
    let parent = @fs.parent_path(abs_path)
    if parent != "/" {
      sh.fs.mkdir_p(parent) catch {
        _ => ()
      }
    }
    sh.fs.write_file(abs_path, data) catch {
      e => raise @bit.GitError::IoError(e.to_string())
    }
  }
  try { sh.ctx.chdir("/") } catch { _ => () }
}

///| snapshot command
pub fn cmd_snapshot(sh : ShellContext, args : Array[String]) -> Int {
  let message = if args.is_empty() { "snapshot" } else { join_args(args) }
  let hash = try {
    let bit_fs = build_bitfs_from_memfs(sh)
    let author = sh.ctx.getenv("USER").unwrap_or("shell")
    let timestamp = sh.next_snapshot_timestamp()
    let snap = bit_fs.snapshot(
      sh.git_store,
      sh.git_store,
      message,
      author,
      timestamp,
    )
    sh.snapshot_head = Some(snap.commit_id)
    snap.commit_id.to_hex()
  } catch {
    e => {
      write_stderr(sh.ctx, "snapshot: " + e.to_string() + "\n")
      return 1
    }
  }
  write_stdout(sh.ctx, hash + "\n")
  0
}

///| rollup command (restore to a snapshot hash)
pub fn cmd_rollup(sh : ShellContext, args : Array[String]) -> Int {
  if args.is_empty() {
    write_stderr(sh.ctx, "rollup: missing commit hash\n")
    return 1
  }
  let hex = args[0]
  let result = try {
    let commit_id = @bit.ObjectId::from_hex(hex)
    let config = @bitfs.FsConfig::local_only()
    let bit_fs = @bitfs.Fs::from_commit(
      sh.git_store,
      git_dir_path(),
      commit_id,
      config=config,
    )
    apply_bitfs_to_memfs(sh, bit_fs)
    sh.snapshot_head = Some(commit_id)
    0
  } catch {
    e => {
      write_stderr(sh.ctx, "rollup: " + e.to_string() + "\n")
      1
    }
  }
  result
}
