///|
/// Export: run
/// Exercises all WASI interfaces and reports results via stdout.
/// Reads /input.txt, writes "processed: <content>" to /output.txt (backward compat),
/// then tests clocks, random, poll, stdin, stderr, environment, and sockets.
pub fn run() -> Result[Unit, Unit] {
  // === filesystem: preopens + types ===
  let dirs = @preopens.get_directories()
  if dirs.length() == 0 {
    return Err(())
  }
  let (root_desc, _) = dirs[0]
  let no_path_flags = @fs.PathFlags::from_bits(0)
  let no_open_flags = @fs.OpenFlags::from_bits(0)
  let read_flags = @fs.Read
  let input_fd = match @fs.descriptor_open_at(
    root_desc,
    no_path_flags,
    "input.txt",
    no_open_flags,
    read_flags,
  ) {
    Ok(fd) => fd
    Err(_) => return Err(())
  }
  let (bytes, _eof) = match @fs.descriptor_read(input_fd, 65536, 0) {
    Ok(result) => result
    Err(_) => return Err(())
  }
  let content = bytes_to_string(bytes)
  let trimmed = trim_end(content)
  let output = "processed: " + trimmed
  let create_flags = @fs.OpenFlags::from_bits(1)
  let write_flags = @fs.Write
  let output_fd = match @fs.descriptor_open_at(
    root_desc,
    no_path_flags,
    "output.txt",
    create_flags,
    write_flags,
  ) {
    Ok(fd) => fd
    Err(_) => return Err(())
  }
  let output_bytes = string_to_bytes(output)
  match @fs.descriptor_write(output_fd, output_bytes, 0) {
    Ok(_) => ()
    Err(_) => return Err(())
  }

  // === cli/stdout ===
  let stdout_stream = @stdout.get_stdout()
  write_line(stdout_stream, output)
  write_line(stdout_stream, "---")

  // === clocks/wall-clock ===
  let wc = @wall_clock.now()
  write_line(
    stdout_stream,
    "wall-clock:now:" + wc.seconds.to_string() + ":" + wc.nanoseconds.to_string(),
  )
  let wc_res = @wall_clock.resolution()
  write_line(
    stdout_stream,
    "wall-clock:resolution:" + wc_res.seconds.to_string() + ":" + wc_res.nanoseconds.to_string(),
  )

  // === clocks/monotonic-clock ===
  let mc_now = @mono_clock.now()
  write_line(stdout_stream, "monotonic-clock:now:" + mc_now.to_string())
  let mc_res = @mono_clock.resolution()
  write_line(
    stdout_stream,
    "monotonic-clock:resolution:" + mc_res.to_string(),
  )
  let mc_pollable = @mono_clock.subscribe_duration(1000UL)
  let mc_ready = @poll.pollable_ready(mc_pollable)
  write_line(
    stdout_stream,
    "monotonic-clock:subscribe_duration:ready:" + mc_ready.to_string(),
  )

  // === random/random ===
  let rand_bytes = @random.get_random_bytes(8UL)
  write_line(
    stdout_stream,
    "random:get_random_bytes:len:" + rand_bytes.length().to_string(),
  )
  let rand_u64 = @random.get_random_u64()
  write_line(
    stdout_stream,
    "random:get_random_u64:" + rand_u64.to_string(),
  )

  // === random/insecure ===
  let insecure_bytes = @insecure.get_insecure_random_bytes(4UL)
  write_line(
    stdout_stream,
    "insecure:get_insecure_random_bytes:len:" + insecure_bytes.length().to_string(),
  )
  let insecure_u64 = @insecure.get_insecure_random_u64()
  write_line(
    stdout_stream,
    "insecure:get_insecure_random_u64:" + insecure_u64.to_string(),
  )

  // === random/insecure-seed ===
  let (seed0, seed1) = @insecure_seed.insecure_seed()
  write_line(
    stdout_stream,
    "insecure-seed:" + seed0.to_string() + ":" + seed1.to_string(),
  )

  // === io/poll ===
  let poll_result = @poll.poll([mc_pollable])
  write_line(
    stdout_stream,
    "poll:len:" + poll_result.length().to_string(),
  )

  // === cli/stdin ===
  let stdin_stream = @stdin.get_stdin()
  let stdin_result = match @streams.input_stream_read(stdin_stream, 1024UL) {
    Ok(data) => "ok:" + data.length().to_string()
    Err(_) => "err"
  }
  write_line(stdout_stream, "stdin:read:" + stdin_result)

  // === cli/stderr ===
  let stderr_stream = @stderr.get_stderr()
  let stderr_msg = string_to_bytes("stderr test output\n")
  let stderr_result = match @streams.output_stream_blocking_write_and_flush(
    stderr_stream,
    stderr_msg,
  ) {
    Ok(_) => "ok"
    Err(_) => "err"
  }
  write_line(stdout_stream, "stderr:write:" + stderr_result)

  // === cli/environment ===
  let args = @environment.get_arguments()
  write_line(
    stdout_stream,
    "environment:args:len:" + args.length().to_string(),
  )
  let env_vars = @environment.get_environment()
  write_line(
    stdout_stream,
    "environment:env:len:" + env_vars.length().to_string(),
  )
  // Output first env var if available
  if env_vars.length() > 0 {
    let (key, value) = env_vars[0]
    write_line(stdout_stream, "environment:env:0:" + key + "=" + value)
  }

  // === sockets/instance-network ===
  // This should throw an error in virtual environment
  // We can't easily catch trap-level errors from FFI, so we skip direct call
  write_line(stdout_stream, "sockets:instance-network:skipped")

  // === sockets/tcp-create-socket ===
  let tcp_result = match @tcp_create.create_tcp_socket(@network.Ipv4) {
    Ok(_) => "ok"
    Err(e) => "err:" + e.to_string()
  }
  write_line(stdout_stream, "sockets:tcp-create:" + tcp_result)

  // === sockets/udp-create-socket ===
  let udp_result = match @udp_create.create_udp_socket(@network.Ipv4) {
    Ok(_) => "ok"
    Err(e) => "err:" + e.to_string()
  }
  write_line(stdout_stream, "sockets:udp-create:" + udp_result)

  // === sockets/ip-name-lookup: skipped (needs Network handle) ===
  write_line(stdout_stream, "sockets:ip-name-lookup:skipped")

  write_line(stdout_stream, "===DONE===")
  Ok(())
}

///|
fn write_line(stream : @streams.OutputStream, msg : String) -> Unit {
  let line = msg + "\n"
  let line_bytes = string_to_bytes(line)
  match @streams.output_stream_blocking_write_and_flush(stream, line_bytes) {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
fn bytes_to_string(bytes : Array[Byte]) -> String {
  let len = bytes.length()
  let ptr = @cabi.cabi_realloc(0, 0, 1, len)
  for i in 0..<len {
    @cabi.cabi_write_u8(ptr + i, bytes[i])
  }
  @cabi.cabi_lift_string(ptr, len)
}

///|
fn string_to_bytes(s : String) -> Array[Byte] {
  let (ptr, len) = @cabi.cabi_lower_string(s)
  let bytes : Array[Byte] = Array::new(capacity=len)
  for i in 0..<len {
    bytes.push(@cabi.cabi_read_u8(ptr + i))
  }
  bytes
}

///|
fn trim_end(s : String) -> String {
  let bytes = string_to_bytes(s)
  let mut end = bytes.length()
  while end > 0 {
    let b = bytes[end - 1].to_int()
    if b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 {
      end = end - 1
    } else {
      break
    }
  }
  if end == bytes.length() {
    return s
  }
  let trimmed : Array[Byte] = Array::new(capacity=end)
  for i in 0..<end {
    trimmed.push(bytes[i])
  }
  bytes_to_string(trimmed)
}
