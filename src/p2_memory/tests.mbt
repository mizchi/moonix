///|
test "io: stdin read returns correct data" {
  let config = P2MemoryConfig::{
    ..P2MemoryConfig::default(),
    stdin: b"\x48\x65\x6c\x6c\x6f",
  }
  let ctx = P2MemoryContext::new(config)
  ctx.io.set_input_stream(0)
  let result = (ctx.io as &@p2.WasiIoStreamsAdapter).input_stream_read(5UL)
  match result {
    Ok(data) => assert_eq(data, b"\x48\x65\x6c\x6c\x6f")
    Err(_) => fail("expected Ok")
  }
}

///|
test "io: stdout write accumulates data" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  ctx.io.set_output_stream(1)
  let _ = (ctx.io as &@p2.WasiIoStreamsAdapter).output_stream_write(
    b"\x41\x42\x43",
  )
  assert_eq(ctx.get_stdout(), b"\x41\x42\x43")
}

///|
test "io: stream closed returns error" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let closed_id = ctx.kernel.alloc_stream(Closed)
  ctx.io.set_input_stream(closed_id)
  let result = (ctx.io as &@p2.WasiIoStreamsAdapter).input_stream_read(10UL)
  assert_true(result is Err(_))
}

///|
test "io: poll returns all ready" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let p1 = @p2.IoPollPollable(0)
  let p2_val = @p2.IoPollPollable(1)
  let result = (ctx.io as &@p2.WasiIoPollAdapter).poll([p1, p2_val])
  match result {
    Ok(indices) => assert_eq(indices.length(), 2)
    Err(_) => fail("expected Ok")
  }
}

///|
test "cli: get_stdin/stdout/stderr return correct stream IDs" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let stdin = (ctx.cli as &@p2.WasiCliStdinAdapter).get_stdin()
  let stdout = (ctx.cli as &@p2.WasiCliStdoutAdapter).get_stdout()
  let stderr = (ctx.cli as &@p2.WasiCliStderrAdapter).get_stderr()
  assert_true(stdin is Ok(_))
  assert_true(stdout is Ok(_))
  assert_true(stderr is Ok(_))
}

///|
test "cli: environment/arguments/cwd" {
  let env : Map[String, String] = {}
  env["HOME"] = "/home/test"
  let config = P2MemoryConfig::{
    ..P2MemoryConfig::default(),
    env,
    args: ["prog", "--flag"],
    cwd: "/tmp",
  }
  let ctx = P2MemoryContext::new(config)
  let env_result = (ctx.cli as &@p2.WasiCliEnvironmentAdapter).get_environment()
  assert_true(env_result is Ok(_))
  let args_result = (ctx.cli as &@p2.WasiCliEnvironmentAdapter).get_arguments()
  match args_result {
    Ok(args) => assert_eq(args.length(), 2)
    Err(_) => fail("expected Ok")
  }
  let cwd_result = (ctx.cli as &@p2.WasiCliEnvironmentAdapter).initial_cwd()
  match cwd_result {
    Ok(Some(cwd)) => assert_eq(cwd, "/tmp")
    _ => fail("expected Some cwd")
  }
}

///|
test "cli: exit_with_code records exit code" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let _ = (ctx.cli as &@p2.WasiCliExitAdapter).exit_with_code(b'\x2a')
  match ctx.get_exit_code() {
    Some(code) => assert_eq(code, 42)
    None => fail("expected exit code")
  }
}

///|
test "fs: write file then stat shows correct size" {
  let fs = @fs.MemFs::new()
  let ctx = P2MemoryContext::new(P2MemoryConfig::default(), fs~)
  fs.write_file("/hello.txt", b"\x48\x69")
  ctx.fs.set_descriptor(0)
  let stat_result = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_stat_at(
    @p2.FilesystemTypesPathFlags(0),
    "hello.txt",
  )
  match stat_result {
    Ok(s) => assert_eq(s.size.0.to_int(), 2)
    Err(_) => fail("expected Ok")
  }
}

///|
test "fs: descriptor_read_via_stream then io read returns data" {
  let fs = @fs.MemFs::new()
  fs.write_file("/test.txt", b"\x41\x42\x43\x44\x45")
  let ctx = P2MemoryContext::new(P2MemoryConfig::default(), fs~)
  let desc_id = ctx.kernel.alloc_descriptor(DescriptorState::{
    path: "/test.txt",
    type_: @p2.FilesystemTypesDescriptorType::RegularFile,
  })
  ctx.fs.set_descriptor(desc_id)
  let stream_result = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_read_via_stream(
    @p2.FilesystemTypesFilesize(0UL),
  )
  match stream_result {
    Ok(stream_ref) => {
      ctx.io.set_input_stream(stream_ref.0)
      let read_result = (ctx.io as &@p2.WasiIoStreamsAdapter).input_stream_read(
        5UL,
      )
      match read_result {
        Ok(data) => assert_eq(data, b"\x41\x42\x43\x44\x45")
        Err(_) => fail("read error")
      }
    }
    Err(_) => fail("stream error")
  }
}

///|
test "fs: mkdir and readdir returns entries" {
  let fs = @fs.MemFs::new()
  let ctx = P2MemoryContext::new(P2MemoryConfig::default(), fs~)
  ctx.fs.set_descriptor(0)
  let _ = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_create_directory_at(
    "subdir",
  )
  fs.write_file("/file.txt", b"\x00")
  let dir_result = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_read_directory()
  match dir_result {
    Ok(ds) => {
      ctx.fs.set_dir_stream(ds.0)
      let mut count = 0
      while true {
        let entry = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).directory_entry_stream_read_directory_entry()
        match entry {
          Ok(Some(_)) => count += 1
          Ok(None) => break
          Err(_) => break
        }
      }
      assert_true(count >= 2)
    }
    Err(_) => fail("readdir error")
  }
}

///|
test "fs: unlink then stat returns error" {
  let fs = @fs.MemFs::new()
  fs.write_file("/todelete.txt", b"\x00")
  let ctx = P2MemoryContext::new(P2MemoryConfig::default(), fs~)
  ctx.fs.set_descriptor(0)
  let _ = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_unlink_file_at(
    "todelete.txt",
  )
  let stat_result = (ctx.fs as &@p2.WasiFilesystemTypesAdapter).descriptor_stat_at(
    @p2.FilesystemTypesPathFlags(0),
    "todelete.txt",
  )
  assert_true(stat_result is Err(_))
}

///|
test "clocks: wall clock now returns configured values" {
  let config = P2MemoryConfig::{
    ..P2MemoryConfig::default(),
    wall_seconds: 1234567890UL,
    wall_nanoseconds: 42,
  }
  let ctx = P2MemoryContext::new(config)
  let result = (ctx.clocks as &@p2.WasiClocksWallClockAdapter).now()
  match result {
    Ok(dt) => {
      assert_eq(dt.seconds, 1234567890UL)
      assert_eq(dt.nanoseconds, 42U)
    }
    Err(_) => fail("expected Ok")
  }
}

///|
test "clocks: monotonic now returns initial value" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let result = (ctx.clocks as &@p2.WasiClocksMonotonicClockAdapter).now()
  match result {
    Ok(instant) => assert_eq(instant.0, 0UL)
    Err(_) => fail("expected Ok")
  }
}

///|
test "clocks: timezone display returns UTC" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let result = (ctx.clocks as &@p2.WasiClocksTimezoneAdapter).display(
    @p2.ClocksTimezoneDatetime(0UL),
  )
  match result {
    Ok(tz) => {
      assert_eq(tz.name, "UTC")
      assert_eq(tz.utc_offset, 0)
    }
    Err(_) => fail("expected Ok")
  }
}

///|
test "random: same seed produces same bytes" {
  let config1 = P2MemoryConfig::{ ..P2MemoryConfig::default(), prng_seed: 99UL }
  let ctx1 = P2MemoryContext::new(config1)
  let config2 = P2MemoryConfig::{ ..P2MemoryConfig::default(), prng_seed: 99UL }
  let ctx2 = P2MemoryContext::new(config2)
  let r1 = (ctx1.random as &@p2.WasiRandomRandomAdapter).get_random_bytes(16UL)
  let r2 = (ctx2.random as &@p2.WasiRandomRandomAdapter).get_random_bytes(16UL)
  match (r1, r2) {
    (Ok(b1), Ok(b2)) => assert_eq(b1, b2)
    _ => fail("expected Ok")
  }
}

///|
test "sockets: create_tcp_socket returns CapabilityDenied" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let result = (ctx.sockets as &@p2.WasiSocketsTcpCreateSocketAdapter).create_tcp_socket(
    @p2.SocketsTcpCreateSocketIpAddressFamily(0),
  )
  assert_true(result is Err(_))
}

///|
test "http: fields CRUD" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let http = ctx.http as &@p2.WasiHttpTypesAdapter
  // constructor
  let _ = http.fields_constructor()
  // set
  let _ = http.fields_set(@p2.HttpTypesFieldName("content-type"), [
    @p2.HttpTypesFieldValue(b"\x74\x65\x78\x74"),
  ])
  // has
  match http.fields_has(@p2.HttpTypesFieldName("content-type")) {
    Ok(v) => assert_true(v)
    Err(_) => fail("expected Ok")
  }
  // get
  match http.fields_get(@p2.HttpTypesFieldName("content-type")) {
    Ok(values) => assert_eq(values.length(), 1)
    Err(_) => fail("expected Ok")
  }
  // append
  let _ = http.fields_append(
    @p2.HttpTypesFieldName("accept"),
    @p2.HttpTypesFieldValue(b"\x2a\x2f\x2a"),
  )
  match http.fields_has(@p2.HttpTypesFieldName("accept")) {
    Ok(v) => assert_true(v)
    Err(_) => fail("expected Ok")
  }
  // delete
  let _ = http.fields_delete(@p2.HttpTypesFieldName("accept"))
  match http.fields_has(@p2.HttpTypesFieldName("accept")) {
    Ok(v) => assert_eq(v, false)
    Err(_) => fail("expected Ok")
  }
  // entries
  match http.fields_entries() {
    Ok(entries) => assert_eq(entries.length(), 1)
    Err(_) => fail("expected Ok")
  }
}

///|
test "http: outgoing request construction" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let http = ctx.http as &@p2.WasiHttpTypesAdapter
  // create fields for headers
  let _ = http.fields_constructor()
  // create outgoing request with current fields (id=0)
  let _ = http.outgoing_request_constructor(@p2.HttpTypesHeaders(0))
  // default method is GET
  match http.outgoing_request_method() {
    Ok(m) => assert_true(m is @p2.HttpTypesMethod::Get)
    Err(_) => fail("expected Ok")
  }
  // default path is /
  match http.outgoing_request_path_with_query() {
    Ok(Some(path)) => assert_eq(path, "/")
    _ => fail("expected Some path")
  }
  // get body
  match http.outgoing_request_body() {
    Ok(_) => ()
    Err(_) => fail("expected Ok")
  }
}

///|
test "http: mock round-trip" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  // register mock handler
  ctx.register_http_handler(fn(_method, _path, _headers, _body) {
    (200, [("x-test", b"\x6f\x6b")], b"\x48\x69")
  })
  let http = ctx.http as &@p2.WasiHttpTypesAdapter
  let handler = ctx.http as &@p2.WasiHttpOutgoingHandlerAdapter
  // create fields + outgoing request
  let _ = http.fields_constructor()
  let _ = http.outgoing_request_constructor(@p2.HttpTypesHeaders(0))
  // handle request
  let future_result = handler.handle(
    @p2.HttpOutgoingHandlerOutgoingRequest(0),
    None,
  )
  match future_result {
    Ok(_) => ()
    Err(_) => fail("handle failed")
  }
  // get response from future
  match http.future_incoming_response_get() {
    Ok(Some(Ok(Ok(resp)))) => {
      ctx.http.current_incoming_response = resp.0
      // check status
      match http.incoming_response_status() {
        Ok(status) => assert_eq(status.0, 200)
        Err(_) => fail("expected status")
      }
    }
    _ => fail("expected response")
  }
}

///|
test "http: body streaming" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  ctx.register_http_handler(fn(_method, _path, _headers, body) {
    // echo body back
    (200, [], body)
  })
  let http = ctx.http as &@p2.WasiHttpTypesAdapter
  let handler = ctx.http as &@p2.WasiHttpOutgoingHandlerAdapter
  let io = ctx.io as &@p2.WasiIoStreamsAdapter
  // create request with body
  let _ = http.fields_constructor()
  let _ = http.outgoing_request_constructor(@p2.HttpTypesHeaders(0))
  let _ = http.outgoing_request_body()
  // write to body via stream
  match http.outgoing_body_write() {
    Ok(stream) => {
      ctx.io.set_output_stream(stream.0)
      let _ = io.output_stream_write(b"\x41\x42\x43\x44\x45")

    }
    Err(_) => fail("expected stream")
  }
  // handle request
  let _ = handler.handle(@p2.HttpOutgoingHandlerOutgoingRequest(0), None)
  // get response
  match http.future_incoming_response_get() {
    Ok(Some(Ok(Ok(resp)))) => {
      ctx.http.current_incoming_response = resp.0
      // consume body
      match http.incoming_response_consume() {
        Ok(body) => {
          // create read stream for body
          let stream_id = ctx.kernel.alloc_stream(HttpBodyRead(body.0))
          ctx.io.set_input_stream(stream_id)
          match io.input_stream_read(10UL) {
            Ok(data) => assert_eq(data, b"\x41\x42\x43\x44\x45")
            Err(_) => fail("read error")
          }
        }
        Err(_) => fail("consume error")
      }
    }
    _ => fail("expected response")
  }
}

///|
test "http: no handler returns 404" {
  let ctx = P2MemoryContext::new(P2MemoryConfig::default())
  let http = ctx.http as &@p2.WasiHttpTypesAdapter
  let handler = ctx.http as &@p2.WasiHttpOutgoingHandlerAdapter
  // create request without registering handler
  let _ = http.fields_constructor()
  let _ = http.outgoing_request_constructor(@p2.HttpTypesHeaders(0))
  let _ = handler.handle(@p2.HttpOutgoingHandlerOutgoingRequest(0), None)
  match http.future_incoming_response_get() {
    Ok(Some(Ok(Ok(resp)))) => {
      ctx.http.current_incoming_response = resp.0
      match http.incoming_response_status() {
        Ok(status) => assert_eq(status.0, 404)
        Err(_) => fail("expected status")
      }
    }
    _ => fail("expected response")
  }
}
