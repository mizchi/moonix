///|
/// WASI Preview2 implementation of `WasiCliHost`.
pub struct WasiPreview2CliHost {}

///|
pub fn WasiPreview2CliHost::new() -> WasiPreview2CliHost {
  WasiPreview2CliHost::{  }
}

///|
fn bytes_to_array(data : Bytes) -> Array[Byte] {
  let arr : Array[Byte] = Array::new(capacity=data.length())
  for byte in data {
    arr.push(byte)
  }
  arr
}

///|
pub impl WasiCliHost for WasiPreview2CliHost with read_stdin(_self, len) {
  let stdin_stream = @stdin.get_stdin()
  match
    @streams.input_stream_blocking_read(
      stdin_stream,
      len.to_int64().reinterpret_as_uint64(),
    ) {
    Ok(bytes) => Bytes::makei(bytes.length(), fn(i) { bytes[i] })
    Err(_) => b""
  }
}

///|
pub impl WasiCliHost for WasiPreview2CliHost with write_stdout(_self, data) {
  let out = @stdout.get_stdout()
  match
    @streams.output_stream_blocking_write_and_flush(out, bytes_to_array(data)) {
    Ok(_) => data.length()
    Err(_) => 0
  }
}

///|
pub impl WasiCliHost for WasiPreview2CliHost with write_stderr(_self, data) {
  let err = @stderr.get_stderr()
  match
    @streams.output_stream_blocking_write_and_flush(err, bytes_to_array(data)) {
    Ok(_) => data.length()
    Err(_) => 0
  }
}
