///| StdStreamHandler implementation over WASI cli stdin/stdout/stderr

pub struct WasiStreamHandler {}

pub fn WasiStreamHandler::new() -> WasiStreamHandler {
  WasiStreamHandler::{  }
}

fn string_to_byte_array(s : String) -> Array[Byte] {
  let arr : Array[Byte] = Array::new(capacity=s.length())
  for i in 0..<s.length() {
    arr.push(s[i].to_int().to_byte())
  }
  arr
}

pub impl @posix.StdStreamHandler for WasiStreamHandler with read(
  _self,
  stream,
  len,
) {
  match stream {
    @posix.Stdin => {
      let stdin_stream = @stdin.get_stdin()
      match @streams.input_stream_blocking_read(stdin_stream, len.to_int64().reinterpret_as_uint64()) {
        Ok(bytes) => Bytes::makei(bytes.length(), fn(i) { bytes[i] })
        Err(_) => b""
      }
    }
    @posix.Stdout | @posix.Stderr => b""
  }
}

pub impl @posix.StdStreamHandler for WasiStreamHandler with write(
  _self,
  stream,
  data,
) {
  let arr : Array[Byte] = Array::new(capacity=data.length())
  for byte in data {
    arr.push(byte)
  }
  match stream {
    @posix.Stdout => {
      let out = @stdout.get_stdout()
      match @streams.output_stream_blocking_write_and_flush(out, arr) {
        Ok(_) => data.length()
        Err(_) => 0
      }
    }
    @posix.Stderr => {
      let err = @stderr.get_stderr()
      match @streams.output_stream_blocking_write_and_flush(err, arr) {
        Ok(_) => data.length()
        Err(_) => 0
      }
    }
    @posix.Stdin => 0
  }
}
