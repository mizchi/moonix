///|
/// Export: run
/// Reads /input.txt, writes "processed: <content>" to /output.txt and stdout.
pub fn run() -> Result[Unit, Unit] {
  // Get preopened directories
  let dirs = @preopens.get_directories()
  if dirs.length() == 0 {
    return Err(())
  }
  let (root_desc, _) = dirs[0]

  // Open and read /input.txt
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

  // Read file content (up to 64KB)
  let (bytes, _eof) = match @fs.descriptor_read(input_fd, 65536, 0) {
    Ok(result) => result
    Err(_) => return Err(())
  }

  // Convert bytes to string (trim trailing whitespace)
  let content = bytes_to_string(bytes)
  let trimmed = trim_end(content)

  // Build output
  let output = "processed: " + trimmed

  // Create and write /output.txt
  let create_flags = @fs.OpenFlags::from_bits(1) // Create
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

  // Write to stdout
  let stdout_stream = @stdout.get_stdout()
  let stdout_line = output + "\n"
  let stdout_bytes = string_to_bytes(stdout_line)
  match @streams.output_stream_blocking_write_and_flush(
    stdout_stream,
    stdout_bytes,
  ) {
    Ok(_) => ()
    Err(_) => ()
  }

  Ok(())
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
