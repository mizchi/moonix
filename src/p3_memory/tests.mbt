///|
test "stdin read returns correct data" {
  let config = P3MemoryConfig::{
    ..P3MemoryConfig::default(),
    stdin: b"\x48\x65\x6c\x6c\x6f",
  }
  let ctx = P3MemoryContext::new(config)
  let result = (ctx.cli as &@p3.WasiStdinAdapter).read_via_stream()
  match result {
    Ok(data) => assert_eq(data, b"\x48\x65\x6c\x6c\x6f")
    Err(_) => fail("expected Ok")
  }
}

///|
test "stdout write accumulates data" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let _ = (ctx.cli as &@p3.WasiStdoutAdapter).write_via_stream(b"\x41\x42\x43")
  assert_eq(ctx.get_stdout(), b"\x41\x42\x43")
}

///|
test "environment / arguments / cwd" {
  let env : Map[String, String] = {}
  env["HOME"] = "/home/test"
  let config = P3MemoryConfig::{
    ..P3MemoryConfig::default(),
    env,
    args: ["prog", "--flag"],
    cwd: "/tmp",
  }
  let ctx = P3MemoryContext::new(config)
  let env_result = (ctx.cli as &@p3.WasiEnvironmentAdapter).get_environment()
  assert_true(env_result is Ok(_))
  let args_result = (ctx.cli as &@p3.WasiEnvironmentAdapter).get_arguments()
  match args_result {
    Ok(args) => assert_eq(args.length(), 2)
    Err(_) => fail("expected Ok")
  }
  let cwd_result = (ctx.cli as &@p3.WasiEnvironmentAdapter).get_initial_cwd()
  match cwd_result {
    Ok(Some(cwd)) => assert_eq(cwd, "/tmp")
    _ => fail("expected Some cwd")
  }
}

///|
test "exit_with_code records exit code" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let _ = (ctx.cli as &@p3.WasiExitAdapter).exit_with_code(b'\x2a')
  match ctx.get_exit_code() {
    Some(code) => assert_eq(code, 42)
    None => fail("expected exit code")
  }
}

///|
test "system clock now returns configured values" {
  let config = P3MemoryConfig::{
    ..P3MemoryConfig::default(),
    wall_seconds: 1234567890UL,
    wall_nanoseconds: 42,
  }
  let ctx = P3MemoryContext::new(config)
  let result = (ctx.clocks as &@p3.WasiClocksSystemClockAdapter).now()
  match result {
    Ok(instant) => {
      assert_eq(instant.seconds, 1234567890L)
      assert_eq(instant.nanoseconds, 42U)
    }
    Err(_) => fail("expected Ok")
  }
}

///|
test "monotonic clock now returns initial value" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let result = (ctx.clocks as &@p3.WasiClocksMonotonicClockAdapter).now()
  match result {
    Ok(mark) => assert_eq(p3_mark_to_u64(mark), 0UL)
    Err(_) => fail("expected Ok")
  }
}

///|
test "timezone iana_id returns UTC" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let result = (ctx.clocks as &@p3.WasiClocksTimezoneAdapter).iana_id()
  match result {
    Ok(Some(id)) => assert_eq(id, "UTC")
    _ => fail("expected Some UTC")
  }
}

///|
test "fs: write then stat then read_via_stream" {
  let fs = @fs.MemFs::new()
  let ctx = P3MemoryContext::new(P3MemoryConfig::default(), fs~)
  fs.write_file("/hello.txt", b"\x48\x69")
  ctx.fs.set_descriptor(0)
  // stat
  let stat_result = (ctx.fs as &@p3.WasiFilesystemTypesAdapter).descriptor_stat_at(
    p3_path_flags_from_uint(0U),
    "hello.txt",
  )
  match stat_result {
    Ok(s) => assert_eq(p3_filesize_to_u64(s.size).to_int(), 2)
    Err(_) => fail("expected Ok stat")
  }
  // read_via_stream
  let desc_id = ctx.kernel.alloc_descriptor(DescriptorState::{
    path: "/hello.txt",
    type_: @p3.FilesystemTypesDescriptorType::RegularFile,
  })
  ctx.fs.set_descriptor(desc_id)
  let read_result = (ctx.fs as &@p3.WasiFilesystemTypesAdapter).descriptor_read_via_stream(
    p3_filesize_from_u64(0UL),
  )
  match read_result {
    Ok(data) => assert_eq(data, b"\x48\x69")
    Err(_) => fail("expected Ok read")
  }
}

///|
test "fs: mkdir + read_directory" {
  let fs = @fs.MemFs::new()
  let ctx = P3MemoryContext::new(P3MemoryConfig::default(), fs~)
  ctx.fs.set_descriptor(0)
  let _ = (ctx.fs as &@p3.WasiFilesystemTypesAdapter).descriptor_create_directory_at(
    "subdir",
  )
  fs.write_file("/file.txt", b"\x00")
  let dir_result = (ctx.fs as &@p3.WasiFilesystemTypesAdapter).descriptor_read_directory()
  match dir_result {
    Ok(data) => assert_true(data.length() > 0)
    Err(_) => fail("readdir error")
  }
}

///|
test "random: same seed produces same bytes" {
  let config1 = P3MemoryConfig::{ ..P3MemoryConfig::default(), prng_seed: 99UL }
  let ctx1 = P3MemoryContext::new(config1)
  let config2 = P3MemoryConfig::{ ..P3MemoryConfig::default(), prng_seed: 99UL }
  let ctx2 = P3MemoryContext::new(config2)
  let r1 = (ctx1.random as &@p3.WasiRandomRandomAdapter).get_random_bytes(16UL)
  let r2 = (ctx2.random as &@p3.WasiRandomRandomAdapter).get_random_bytes(16UL)
  match (r1, r2) {
    (Ok(b1), Ok(b2)) => assert_eq(b1, b2)
    _ => fail("expected Ok")
  }
}

///|
test "network: resolve_addresses returns deny" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let result = (ctx.network as &@p3.WasiIpNameLookupAdapter).resolve_addresses(
    "example.com",
  )
  assert_true(result is Err(_))
}

///|
test "http: fields CRUD" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  let http = ctx.http as &@p3.WasiHttpTypesAdapter
  // constructor
  let _ = http.fields_constructor()
  // set
  let _ = http.fields_set(p3_field_name_from_string("content-type"), [
    p3_field_value_from_bytes(b"\x74\x65\x78\x74"),
  ])
  // has
  match http.fields_has(p3_field_name_from_string("content-type")) {
    Ok(v) => assert_true(v)
    Err(_) => fail("expected Ok")
  }
  // get
  match http.fields_get(p3_field_name_from_string("content-type")) {
    Ok(values) => assert_eq(values.length(), 1)
    Err(_) => fail("expected Ok")
  }
  // append
  let _ = http.fields_append(
    p3_field_name_from_string("accept"),
    p3_field_value_from_bytes(b"\x2a\x2f\x2a"),
  )
  match http.fields_has(p3_field_name_from_string("accept")) {
    Ok(v) => assert_true(v)
    Err(_) => fail("expected Ok")
  }
  // get_and_delete
  match http.fields_get_and_delete(p3_field_name_from_string("accept")) {
    Ok(values) => assert_eq(values.length(), 1)
    Err(_) => fail("expected Ok")
  }
  match http.fields_has(p3_field_name_from_string("accept")) {
    Ok(v) => assert_eq(v, false)
    Err(_) => fail("expected Ok")
  }
}

///|
test "http: mock round-trip" {
  let ctx = P3MemoryContext::new(P3MemoryConfig::default())
  ctx.register_http_handler(fn(_method, _path, _headers, _body) {
    (200, [("x-test", b"\x6f\x6b")], b"\x48\x69")
  })
  let http = ctx.http as &@p3.WasiHttpTypesAdapter
  let client = ctx.http as &@p3.WasiHttpClientAdapter
  // create fields + request
  let _ = http.fields_constructor()
  let _ = http.request_new(p3_headers_from_int(0), None, Ok(None), None)
  // send request
  let send_result = client.send(@p3.HttpTypesRequest(0))
  match send_result {
    Ok(resp) => {
      ctx.http.current_response = resp.0
      // check status
      match http.response_get_status_code() {
        Ok(status) => assert_eq(p3_status_code_to_int(status), 200)
        Err(_) => fail("expected status")
      }
      // consume body
      match http.response_consume_body(resp, Ok(())) {
        Ok(body) => assert_eq(body, b"\x48\x69")
        Err(_) => fail("expected body")
      }
    }
    Err(_) => fail("send failed")
  }
}
