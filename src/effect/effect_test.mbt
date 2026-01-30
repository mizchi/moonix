///| Tests for Effect Log

test "EffectLog::new creates empty log" {
  let log = EffectLog::new()
  assert_eq(log.length(), 0)
  assert_eq(log.head(), 0)
}

test "EffectLog::record adds entry" {
  let log = EffectLog::new()
  let mut ts = 1000L
  log.set_timestamp_provider(fn() {
    let t = ts
    ts = ts + 100L
    t
  })

  let entry = log.record_http(
    "GET",
    "https://api.example.com/data",
    Some(200),
    None,
    None,
  )

  assert_eq(log.length(), 1)
  assert_eq(entry.seq, 0)
  assert_eq(entry.timestamp, 1000L)
}

test "EffectLog::record_mcp tracks tool calls" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 2000L })

  let entry = log.record_mcp(
    "file_read",
    Some("{\"path\": \"/path/to/file\"}"),
    Some("\"file contents\""),
  )

  assert_eq(log.length(), 1)
  match entry.kind {
    McpToolCall(data) => assert_eq(data.tool, "file_read")
    _ => fail("Expected McpToolCall")
  }
}

test "EffectLog::entries_after filters by head position" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 1000L })

  let _ = log.record_clock(1000L)  // seq 0
  let _ = log.record_clock(2000L)  // seq 1
  let _ = log.record_clock(3000L)  // seq 2

  // entries_after(1) returns entries with seq >= 1
  let after = log.entries_after(1)
  assert_eq(after.length(), 2)
  assert_eq(after[0].seq, 1)
  assert_eq(after[1].seq, 2)

  // entries_after(0) returns all entries
  let all = log.entries_after(0)
  assert_eq(all.length(), 3)
}

test "EffectLog::http_effects filters HTTP only" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 1000L })

  let _ = log.record_http("GET", "https://api.com", Some(200), None, None)
  let _ = log.record_clock(1000L)
  let _ = log.record_http("POST", "https://api.com", Some(201), None, None)
  let _ = log.record_random(b"random")

  let http = log.http_effects()
  assert_eq(http.length(), 2)
}

test "EffectLog::set_current_snapshot tracks parent" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 1000L })
  log.set_current_snapshot(Some("abc123"))

  let entry = log.record_clock(1000L)

  match entry.parent_snapshot {
    Some(s) => assert_eq(s, "abc123")
    None => fail("Expected parent snapshot")
  }
}

test "EffectLog::record_process tracks process spawn" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 1000L })

  let entry = log.record_process("ls", ["-la", "/tmp"], Some(0))

  match entry.kind {
    ProcessSpawn(cmd, args, exit_code) => {
      assert_eq(cmd, "ls")
      assert_eq(args.length(), 2)
      assert_eq(exit_code, Some(0))
    }
    _ => fail("Expected ProcessSpawn")
  }
}

test "EffectLog::clear removes all entries" {
  let log = EffectLog::new()
  log.set_timestamp_provider(fn() { 1000L })

  let _ = log.record_clock(1000L)
  let _ = log.record_clock(2000L)
  assert_eq(log.length(), 2)

  log.clear()
  assert_eq(log.length(), 0)
  assert_eq(log.head(), 0)
}
