///| Demo: Side effects and rollback

test "Demo: rollback with irreversible effects" {
  let rt = @runtime.AgentRuntime::unrestricted()

  // タイムスタンプのモック
  let mut ts = 1000L
  rt.set_timestamp_provider(fn() {
    let t = ts
    ts = ts + 100L
    t
  })

  // === Phase 1: 初期状態を作成 ===
  println("=== Phase 1: Initial setup ===")
  rt.mkdir_p("/home/agent")
  rt.write_string("/home/agent/config.json", "{\"version\": 1}")
  rt.write_string("/home/agent/data.txt", "original data")

  let snap_initial = rt.snapshot("Initial state")
  println("Snapshot created: " + snap_initial.git_snapshot.message)
  println("Files: config.json, data.txt")
  println("")

  // === Phase 2: ファイル変更 + 外部効果を起こす ===
  println("=== Phase 2: Make changes and side effects ===")

  // ファイル変更（ロールバック可能 - コミットなしでも復元される）
  rt.write_string("/home/agent/config.json", "{\"version\": 2}")
  rt.write_string("/home/agent/new_file.txt", "created after snapshot")
  println("File changes: config.json updated, new_file.txt created (uncommitted)")

  // 外部効果（ロールバック不可）
  // 1. 現在時刻の取得
  let time = rt.wall_clock()
  println("Side effect 1: wall_clock() -> \{time}")

  // 2. 乱数生成
  let random = rt.random_bytes(8)
  println("Side effect 2: random_bytes(8) -> \{random.length()} bytes")

  // 3. HTTP リクエスト（モック）
  let http_response = rt.http_request(
    "POST",
    "https://api.example.com/notify",
    Some(b"{\"message\": \"hello\"}"),
    fn(_method, _url, _body) { { status: 200, body: b"ok" } },
  )
  println("Side effect 3: HTTP POST -> status \{http_response.status}")

  // 4. MCP ツール呼び出し（モック）
  let mcp_result = rt.mcp_call(
    "slack_post",
    Some("{\"channel\": \"#general\", \"text\": \"Hello!\"}"),
    fn(_tool, _input) { { success: true, output: Some("message sent"), error: None } },
  )
  println("Side effect 4: MCP slack_post -> success=\{mcp_result.success}")

  println("")

  // === Phase 3: 状態確認 ===
  println("=== Phase 3: Current state ===")
  let config_content = rt.read_string("/home/agent/config.json")
  let new_file_exists = rt.exists("/home/agent/new_file.txt")
  let effect_count = rt.get_effects().length()
  println("config.json: " + config_content)
  println("new_file.txt exists: " + new_file_exists.to_string())
  println("Effect log entries: " + effect_count.to_string())
  println("")

  // === Phase 4: ロールバック ===
  println("=== Phase 4: Rollback to initial state ===")
  let rollback_result = rt.rollback(snap_initial)

  println("Filesystem restored: \{rollback_result.restored_fs}")
  println("Irreversible effects count: \{rollback_result.irreversible_effects.length()}")

  match rollback_result.warning {
    Some(w) => println("Warning: \{w}")
    None => println("No warning")
  }
  println("")

  // === Phase 5: ロールバック後の状態確認 ===
  println("=== Phase 5: State after rollback ===")
  let config_after = rt.read_string("/home/agent/config.json")
  let new_file_after = rt.exists("/home/agent/new_file.txt")
  println("config.json: " + config_after)
  println("new_file.txt exists: " + new_file_after.to_string())
  println("")

  // === Phase 6: 不可逆な効果の詳細 ===
  println("=== Phase 6: Irreversible effects detail ===")
  for i, effect in rollback_result.irreversible_effects {
    let kind_str = match effect.kind {
      @effect.WallClockRead(t) => "WallClockRead(\{t})"
      @effect.RandomGenerate(b) => "RandomGenerate(\{b.length()} bytes)"
      @effect.HttpRequest(data) => "HttpRequest(\{data.http_method} \{data.url})"
      @effect.McpToolCall(data) => "McpToolCall(\{data.tool})"
      _ => "Other"
    }
    println("  [\{i}] \{kind_str}")
  }

  // 検証
  assert_true(rollback_result.restored_fs)
  assert_eq(rollback_result.irreversible_effects.length(), 4)
  let expected_config = "{\"version\": 1}"
  assert_eq(rt.read_string("/home/agent/config.json"), expected_config)
  assert_false(rt.exists("/home/agent/new_file.txt"))
}

test "Rollback: comprehensive file operations" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // === Initial Setup ===
  println("=== Initial Setup ===")
  rt.mkdir_p("/project")
  rt.write_string("/project/readme.md", "# Project")
  rt.write_string("/project/config.json", "{\"v\": 1}")

  let snap = rt.snapshot("Initial")
  println("Snapshot: Initial state with /project/readme.md, /project/config.json")

  // === Various File Operations ===
  println("")
  println("=== Performing various file operations ===")

  // 1. Create new files
  rt.write_string("/project/new_file.txt", "new content")
  println("1. Created /project/new_file.txt")

  // 2. Create nested directories with files
  rt.mkdir_p("/project/src/lib/utils")
  rt.write_string("/project/src/main.mbt", "fn main() {}")
  rt.write_string("/project/src/lib/helper.mbt", "fn helper() {}")
  rt.write_string("/project/src/lib/utils/string.mbt", "fn trim() {}")
  println("2. Created nested /project/src/** with 3 files")

  // 3. Modify existing file multiple times
  rt.write_string("/project/config.json", "{\"v\": 2}")
  rt.write_string("/project/config.json", "{\"v\": 3}")
  rt.write_string("/project/config.json", "{\"v\": 4, \"updated\": true}")
  println("3. Modified /project/config.json 3 times (v1 -> v4)")

  // 4. Delete a file
  rt.remove("/project/readme.md")
  println("4. Deleted /project/readme.md")

  // 5. Create and then delete a directory
  rt.mkdir_p("/project/temp")
  rt.write_string("/project/temp/cache.txt", "cached data")
  rt.rm_rf("/project/temp")
  println("5. Created and deleted /project/temp/")

  // 6. Create binary-like content
  rt.write_file("/project/data.bin", b"\x00\x01\x02\x03\xff\xfe")
  println("6. Created /project/data.bin with binary content")

  // 7. Empty file
  rt.write_string("/project/empty.txt", "")
  println("7. Created empty /project/empty.txt")

  // 8. Large content
  let large = StringBuilder::new()
  for i = 0; i < 100; i = i + 1 {
    large.write_string("Line ")
    large.write_string(i.to_string())
    large.write_string(": Lorem ipsum dolor sit amet\n")
  }
  rt.write_string("/project/large.txt", large.to_string())
  println("8. Created /project/large.txt with 100 lines")

  // Commit all changes so they're tracked
  let _ = rt.snapshot("After changes")

  // === Verify State Before Rollback ===
  println("")
  println("=== State before rollback ===")
  assert_true(rt.exists("/project/new_file.txt"))
  assert_true(rt.exists("/project/src/main.mbt"))
  assert_true(rt.exists("/project/src/lib/helper.mbt"))
  assert_true(rt.exists("/project/src/lib/utils/string.mbt"))
  assert_eq(rt.read_string("/project/config.json"), "{\"v\": 4, \"updated\": true}")
  assert_false(rt.exists("/project/readme.md"))
  assert_false(rt.exists("/project/temp"))
  assert_true(rt.exists("/project/data.bin"))
  assert_true(rt.exists("/project/empty.txt"))
  assert_true(rt.exists("/project/large.txt"))
  println("All assertions passed: 10 checks")

  // === Rollback ===
  println("")
  println("=== Rolling back to initial state ===")
  let result = rt.rollback(snap)
  assert_true(result.restored_fs)
  println("Filesystem restored: true")

  // === Verify State After Rollback ===
  println("")
  println("=== State after rollback ===")

  // 1. New file should be gone
  assert_false(rt.exists("/project/new_file.txt"))
  println("1. /project/new_file.txt: deleted (correct)")

  // 2. Nested directory files should be gone
  assert_false(rt.exists("/project/src/main.mbt"))
  assert_false(rt.exists("/project/src/lib/helper.mbt"))
  assert_false(rt.exists("/project/src/lib/utils/string.mbt"))
  println("2. /project/src/** files: deleted (correct)")

  // 3. Config should be back to v1
  let expected_config = "{\"v\": 1}"
  assert_eq(rt.read_string("/project/config.json"), expected_config)
  println("3. /project/config.json: restored to v1 (correct)")

  // 4. Deleted file should be restored
  assert_true(rt.exists("/project/readme.md"))
  assert_eq(rt.read_string("/project/readme.md"), "# Project")
  println("4. /project/readme.md: restored (correct)")

  // 5. Temp directory stays gone (was created and deleted)
  assert_false(rt.exists("/project/temp"))
  println("5. /project/temp: stays deleted (correct)")

  // 6. Binary file should be gone
  assert_false(rt.exists("/project/data.bin"))
  println("6. /project/data.bin: deleted (correct)")

  // 7. Empty file should be gone
  assert_false(rt.exists("/project/empty.txt"))
  println("7. /project/empty.txt: deleted (correct)")

  // 8. Large file should be gone
  assert_false(rt.exists("/project/large.txt"))
  println("8. /project/large.txt: deleted (correct)")

  // Verify expected files exist
  let files = rt.readdir("/project")
  let file_count = files.length()
  // Note: Empty directories may remain after rollback (git behavior)
  // The important thing is that FILE contents are correctly restored
  assert_true(file_count >= 2) // At least readme.md and config.json
  println("9. /project/ has " + file_count.to_string() + " entries (files restored, empty dirs may remain)")

  println("")
  println("=== All rollback tests passed! ===")
}

test "Rollback: multiple snapshots and selective rollback" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Create base state
  rt.mkdir_p("/data")
  rt.write_string("/data/counter.txt", "0")
  let snap0 = rt.snapshot("counter=0")

  // Increment to 1
  rt.write_string("/data/counter.txt", "1")
  rt.write_string("/data/log.txt", "step1")
  let snap1 = rt.snapshot("counter=1")

  // Increment to 2
  rt.write_string("/data/counter.txt", "2")
  rt.write_string("/data/log.txt", "step1\nstep2")
  let snap2 = rt.snapshot("counter=2")

  // Increment to 3
  rt.write_string("/data/counter.txt", "3")
  rt.write_string("/data/log.txt", "step1\nstep2\nstep3")
  let _ = rt.snapshot("counter=3")

  println("=== Created 4 snapshots (counter 0->1->2->3) ===")

  // Verify current state
  assert_eq(rt.read_string("/data/counter.txt"), "3")
  println("Current counter: 3")

  // Rollback to snap2 (counter=2)
  println("")
  println("=== Rollback to counter=2 ===")
  let _ = rt.rollback(snap2)
  assert_eq(rt.read_string("/data/counter.txt"), "2")
  assert_eq(rt.read_string("/data/log.txt"), "step1\nstep2")
  println("Counter: 2, Log has 2 entries (correct)")

  // Rollback to snap1 (counter=1)
  println("")
  println("=== Rollback to counter=1 ===")
  let _ = rt.rollback(snap1)
  assert_eq(rt.read_string("/data/counter.txt"), "1")
  assert_eq(rt.read_string("/data/log.txt"), "step1")
  println("Counter: 1, Log has 1 entry (correct)")

  // Rollback to snap0 (counter=0)
  println("")
  println("=== Rollback to counter=0 ===")
  let _ = rt.rollback(snap0)
  assert_eq(rt.read_string("/data/counter.txt"), "0")
  assert_false(rt.exists("/data/log.txt")) // log.txt didn't exist at snap0
  println("Counter: 0, Log file deleted (correct)")

  println("")
  println("=== Selective rollback tests passed! ===")
}

test "Rollback: directory operations" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Initial: /workspace with one file
  rt.mkdir_p("/workspace")
  rt.write_string("/workspace/root.txt", "root file")
  let snap_initial = rt.snapshot("initial workspace")

  // Add nested structure
  rt.mkdir_p("/workspace/a/b/c")
  rt.mkdir_p("/workspace/x/y")
  rt.write_string("/workspace/a/file1.txt", "in a")
  rt.write_string("/workspace/a/b/file2.txt", "in a/b")
  rt.write_string("/workspace/a/b/c/file3.txt", "in a/b/c")
  rt.write_string("/workspace/x/file4.txt", "in x")
  let _ = rt.snapshot("with structure")

  println("=== Created nested structure ===")
  println("/workspace/a/b/c/file3.txt exists: " + rt.exists("/workspace/a/b/c/file3.txt").to_string())

  // Verify structure exists
  assert_true(rt.exists("/workspace/a/file1.txt"))
  assert_true(rt.exists("/workspace/a/b/file2.txt"))
  assert_true(rt.exists("/workspace/a/b/c/file3.txt"))
  assert_true(rt.exists("/workspace/x/file4.txt"))
  assert_eq(rt.read_string("/workspace/a/b/c/file3.txt"), "in a/b/c")

  // Rollback to initial
  println("")
  println("=== Rollback to initial workspace ===")
  let _ = rt.rollback(snap_initial)

  // Verify nested files are gone
  assert_false(rt.exists("/workspace/a/file1.txt"))
  assert_false(rt.exists("/workspace/a/b/file2.txt"))
  assert_false(rt.exists("/workspace/a/b/c/file3.txt"))
  assert_false(rt.exists("/workspace/x/file4.txt"))
  println("Nested files deleted: correct")

  // Root file should still exist
  assert_true(rt.exists("/workspace/root.txt"))
  assert_eq(rt.read_string("/workspace/root.txt"), "root file")
  println("/workspace/root.txt restored: correct")

  println("")
  println("=== Directory rollback tests passed! ===")
}

test "Rollback: uncommitted changes are reverted" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Create initial state
  rt.mkdir_p("/work")
  rt.write_string("/work/original.txt", "original content")
  let snap = rt.snapshot("initial")

  println("=== Initial state committed ===")
  assert_eq(rt.read_string("/work/original.txt"), "original content")

  // Make uncommitted changes (NO snapshot after these!)
  rt.write_string("/work/original.txt", "modified content") // Modify existing
  rt.write_string("/work/new1.txt", "new file 1")           // Create new file
  rt.write_string("/work/new2.txt", "new file 2")           // Create another
  rt.mkdir_p("/work/newdir")
  rt.write_string("/work/newdir/nested.txt", "nested file") // Nested new file

  println("=== Uncommitted changes made ===")
  assert_eq(rt.read_string("/work/original.txt"), "modified content")
  assert_true(rt.exists("/work/new1.txt"))
  assert_true(rt.exists("/work/new2.txt"))
  assert_true(rt.exists("/work/newdir/nested.txt"))

  // Rollback WITHOUT committing the changes
  println("")
  println("=== Rollback (uncommitted changes should be reverted) ===")
  let _ = rt.rollback(snap)

  // Verify: modified file restored
  assert_eq(rt.read_string("/work/original.txt"), "original content")
  println("original.txt: restored to original content (correct)")

  // Verify: new files removed
  assert_false(rt.exists("/work/new1.txt"))
  assert_false(rt.exists("/work/new2.txt"))
  assert_false(rt.exists("/work/newdir/nested.txt"))
  println("new1.txt, new2.txt, nested.txt: all deleted (correct)")

  println("")
  println("=== Uncommitted changes rollback passed! ===")
}

test "Rollback: file content preservation" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  rt.mkdir_p("/test")

  // Test various content types
  let text_content = "Hello, World!\nLine 2\n\tIndented"
  let json_content = "{\"key\": \"value\", \"nested\": {\"arr\": [1, 2, 3]}}"
  let special_content = "Special chars: <>&\"' \t\n\r end"
  let binary_content = b"\x00\x01\x02\x03\x04\x05"

  rt.write_string("/test/text.txt", text_content)
  rt.write_string("/test/data.json", json_content)
  rt.write_string("/test/special.txt", special_content)
  rt.write_file("/test/binary.dat", binary_content)

  let snap = rt.snapshot("with content")

  // Corrupt all files
  rt.write_string("/test/text.txt", "CORRUPTED")
  rt.write_string("/test/data.json", "CORRUPTED")
  rt.write_string("/test/special.txt", "CORRUPTED")
  rt.write_file("/test/binary.dat", b"CORRUPTED")
  let _ = rt.snapshot("corrupted")

  println("=== Files corrupted ===")
  assert_eq(rt.read_string("/test/text.txt"), "CORRUPTED")

  // Rollback
  println("=== Rollback to original ===")
  let _ = rt.rollback(snap)

  // Verify content restored exactly
  assert_eq(rt.read_string("/test/text.txt"), text_content)
  assert_eq(rt.read_string("/test/data.json"), json_content)
  assert_eq(rt.read_string("/test/special.txt"), special_content)
  assert_eq(rt.read_file("/test/binary.dat"), binary_content)

  println("text.txt: restored (correct)")
  println("data.json: restored (correct)")
  println("special.txt: restored (correct)")
  println("binary.dat: restored (correct)")

  println("")
  println("=== Content preservation tests passed! ===")
}

test "Fork: branch from any snapshot" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Setup: Create initial state
  rt.mkdir_p("/app")
  rt.write_string("/app/version.txt", "v1.0")
  let snap_v1 = rt.snapshot("version 1.0")

  // Create explicit "main" branch at this point
  rt.branch("main")
  println("=== Created v1.0, main branch ===")

  // Continue on main: v1.0 -> v2.0
  rt.write_string("/app/version.txt", "v2.0")
  rt.write_string("/app/feature_a.txt", "Feature A")
  let snap_v2 = rt.snapshot("version 2.0")
  println("=== Created v2.0 (main) ===")

  // Continue: v2.0 -> v3.0
  rt.write_string("/app/version.txt", "v3.0")
  rt.write_string("/app/feature_b.txt", "Feature B")
  let snap_v3 = rt.snapshot("version 3.0")
  println("=== Created v3.0 (main) ===")

  // Verify current state
  assert_eq(rt.read_string("/app/version.txt"), "v3.0")
  assert_true(rt.exists("/app/feature_a.txt"))
  assert_true(rt.exists("/app/feature_b.txt"))
  println("Current: v3.0 with features A, B")

  // Fork from v1.0 to create "experiment" branch
  println("")
  println("=== Fork from v1.0 to 'experiment' branch ===")
  rt.fork(snap_v1, "experiment")

  // Verify we're now at v1.0 on experiment branch
  assert_eq(rt.read_string("/app/version.txt"), "v1.0")
  assert_false(rt.exists("/app/feature_a.txt"))
  assert_false(rt.exists("/app/feature_b.txt"))
  let branch = rt.current_branch()
  assert_eq(branch, Some("experiment"))
  println("Now on 'experiment' branch at v1.0")

  // Work on experiment branch: different direction
  rt.write_string("/app/version.txt", "v1.1-exp")
  rt.write_string("/app/experiment.txt", "Experimental feature")
  let _ = rt.snapshot("experiment v1.1")
  println("Created v1.1-exp with experimental feature")

  // Verify experiment state
  assert_eq(rt.read_string("/app/version.txt"), "v1.1-exp")
  assert_true(rt.exists("/app/experiment.txt"))
  assert_false(rt.exists("/app/feature_a.txt"))

  // Can rollback to v2.0 (from main branch history)
  println("")
  println("=== Rollback to v2.0 ===")
  let _ = rt.rollback(snap_v2)
  assert_eq(rt.read_string("/app/version.txt"), "v2.0")
  assert_true(rt.exists("/app/feature_a.txt"))
  assert_false(rt.exists("/app/feature_b.txt"))
  assert_false(rt.exists("/app/experiment.txt"))
  println("At v2.0: Feature A, no Feature B, no experiment")

  // Can rollback to v3.0
  println("")
  println("=== Rollback to v3.0 ===")
  let _ = rt.rollback(snap_v3)
  assert_eq(rt.read_string("/app/version.txt"), "v3.0")
  assert_true(rt.exists("/app/feature_a.txt"))
  assert_true(rt.exists("/app/feature_b.txt"))
  println("At v3.0: Features A and B")

  // List branches (may throw if refs/heads doesn't exist)
  let branches = try {
    rt.list_branches()
  } catch {
    _ => []
  }
  println("Branches: " + branches.length().to_string())

  println("")
  println("=== Fork test passed! ===")
}

test "Fork: fork_here creates branch at current state" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Setup
  rt.mkdir_p("/work")
  rt.write_string("/work/data.txt", "initial")
  let _ = rt.snapshot("initial")

  // Make changes
  rt.write_string("/work/data.txt", "modified")
  rt.write_string("/work/new.txt", "new file")

  // Fork here (commits current changes and creates branch)
  println("=== fork_here with uncommitted changes ===")
  let fork_snap = rt.fork_here("feature", message="feature branch")

  // Verify we're on the new branch
  let branch = rt.current_branch()
  assert_eq(branch, Some("feature"))
  println("Now on 'feature' branch")

  // Verify state was preserved
  assert_eq(rt.read_string("/work/data.txt"), "modified")
  assert_true(rt.exists("/work/new.txt"))
  println("State preserved after fork")

  // Make more changes on feature branch
  rt.write_string("/work/feature.txt", "feature work")
  let _ = rt.snapshot("feature work")

  // Go back to fork point
  println("")
  println("=== Rollback to fork point ===")
  let _ = rt.rollback(fork_snap)

  // Should still have modified/new but not feature.txt
  assert_eq(rt.read_string("/work/data.txt"), "modified")
  assert_true(rt.exists("/work/new.txt"))
  assert_false(rt.exists("/work/feature.txt"))
  println("Rolled back to fork point correctly")

  println("")
  println("=== fork_here test passed! ===")
}

test "Fork: parallel exploration" {
  let rt = @runtime.AgentRuntime::unrestricted()
  rt.set_timestamp_provider(fn() { 1000L })

  // Create base state
  rt.mkdir_p("/project")
  rt.write_string("/project/config.json", "{\"approach\": \"base\"}")
  let base_snap = rt.snapshot("base")
  println("=== Base state created ===")

  // Explore approach A
  rt.write_string("/project/config.json", "{\"approach\": \"A\"}")
  rt.write_string("/project/approach_a.txt", "Implementation A")
  let snap_a = rt.snapshot("approach A")
  println("Explored approach A")

  // Fork from base to explore approach B
  println("")
  println("=== Fork from base to explore approach B ===")
  rt.fork(base_snap, "approach-b")

  rt.write_string("/project/config.json", "{\"approach\": \"B\"}")
  rt.write_string("/project/approach_b.txt", "Implementation B")
  let snap_b = rt.snapshot("approach B")
  println("Explored approach B")

  // Verify approach B state
  let config_b = rt.read_string("/project/config.json")
  assert_true(config_b.contains("B"))
  assert_true(rt.exists("/project/approach_b.txt"))
  assert_false(rt.exists("/project/approach_a.txt"))

  // Can go back to approach A
  println("")
  println("=== Rollback to approach A ===")
  let _ = rt.rollback(snap_a)

  let config_a = rt.read_string("/project/config.json")
  assert_true(config_a.contains("A"))
  assert_true(rt.exists("/project/approach_a.txt"))
  assert_false(rt.exists("/project/approach_b.txt"))
  println("Back to approach A")

  // Can go back to approach B
  println("")
  println("=== Rollback to approach B ===")
  let _ = rt.rollback(snap_b)

  let config_b2 = rt.read_string("/project/config.json")
  assert_true(config_b2.contains("B"))
  assert_true(rt.exists("/project/approach_b.txt"))
  assert_false(rt.exists("/project/approach_a.txt"))
  println("Back to approach B")

  println("")
  println("=== Parallel exploration test passed! ===")
}

test "Demo: sandbox capability restrictions" {
  let rt = @runtime.AgentRuntime::sandbox()
  rt.set_timestamp_provider(fn() { 1000L })

  println("=== Sandbox mode demo ===")

  // /tmp への書き込みは許可
  rt.mkdir_p("/tmp")
  rt.write_string("/tmp/allowed.txt", "this works")
  println("/tmp/allowed.txt written successfully")

  // /etc への書き込みは拒否される
  let result = try {
    rt.write_string("/etc/passwd", "hacked")
    Ok(())
  } catch {
    @runtime.PermissionDenied(path) => {
      println("Permission denied for: " + path)
      Err("denied")
    }
    _ => Err("other error")
  }

  assert_true(result is Err(_))
  println("")

  // クロック読み取りは許可（sandbox は clock_read 許可）
  let time = rt.wall_clock()
  println("wall_clock() allowed: " + time.to_string())

  // MCP 呼び出しは拒否される（sandbox は MCP 許可なし）
  let mcp_result = try {
    let _ = rt.mcp_call("any_tool", None, fn(_, _) {
      { success: true, output: None, error: None }
    })
    Ok(())
  } catch {
    @runtime.PermissionDenied(msg) => {
      println("MCP denied: " + msg)
      Err("denied")
    }
    _ => Err("other error")
  }

  assert_true(mcp_result is Err(_))
}

test "Demo: agent mode with specific capabilities" {
  // 特定の MCP ツールとホストのみ許可するエージェント
  let config = @runtime.RuntimeConfig::agent(
    "demo-agent",
    ["file_read", "web_search"],  // 許可する MCP ツール
    ["helper-agent"],              // 許可する A2A エージェント
    ["api.openai.com", "api.anthropic.com"],  // 許可するホスト
  )
  let rt = @runtime.AgentRuntime::new(config)
  rt.set_timestamp_provider(fn() { 1000L })

  println("=== Agent mode with specific capabilities ===")

  // 許可されたツール
  let mcp_input = "{\"path\": \"/data\"}"
  let result1 = rt.mcp_call("file_read", Some(mcp_input), fn(_, _) {
    { success: true, output: Some("file content"), error: None }
  })
  println("file_read: success=" + result1.success.to_string())

  // 許可されていないツール
  let result2 = try {
    let _ = rt.mcp_call("shell_exec", Some("rm -rf /"), fn(_, _) {
      { success: true, output: None, error: None }
    })
    Ok(())
  } catch {
    @runtime.PermissionDenied(msg) => {
      println("shell_exec denied: " + msg)
      Err("denied")
    }
    _ => Err("other")
  }
  assert_true(result2 is Err(_))

  // 許可されたホストへの HTTP
  let http1 = rt.http_request("GET", "https://api.openai.com/v1/models", None, fn(_, _, _) {
    { status: 200, body: b"[]" }
  })
  println("api.openai.com: status=" + http1.status.to_string())

  // 許可されていないホストへの HTTP
  let http2 = try {
    let _ = rt.http_request("GET", "https://evil.com/steal", None, fn(_, _, _) {
      { status: 200, body: b"" }
    })
    Ok(())
  } catch {
    @runtime.PermissionDenied(msg) => {
      println("evil.com denied: " + msg)
      Err("denied")
    }
    _ => Err("other")
  }
  assert_true(http2 is Err(_))
}
