///|
pub struct IoAdapter {
  kernel : Kernel
  mut current_input_stream : Int
  mut current_output_stream : Int
  mut current_error : Int
  mut current_pollable : Int
}

///|
pub fn IoAdapter::new(kernel : Kernel) -> IoAdapter {
  {
    kernel,
    current_input_stream: 0,
    current_output_stream: 1,
    current_error: 0,
    current_pollable: 0,
  }
}

///|
pub fn IoAdapter::set_input_stream(self : IoAdapter, id : Int) -> Unit {
  self.current_input_stream = id
}

///|
pub fn IoAdapter::set_output_stream(self : IoAdapter, id : Int) -> Unit {
  self.current_output_stream = id
}

///|
pub fn IoAdapter::set_error(self : IoAdapter, id : Int) -> Unit {
  self.current_error = id
}

///|
pub fn IoAdapter::set_pollable(self : IoAdapter, id : Int) -> Unit {
  self.current_pollable = id
}

///|
fn IoAdapter::read_from_stream(
  self : IoAdapter,
  len : UInt64,
) -> Result[Bytes, @p2.WasiError] {
  let id = self.current_input_stream
  match self.kernel.streams.get(id) {
    None => Err(stream_closed_error())
    Some(Closed) => Err(stream_closed_error())
    Some(StdinStream) => {
      let avail = self.kernel.stdin_data.length() - self.kernel.stdin_pos
      if avail <= 0 {
        return Ok(b"")
      }
      let to_read = if len.to_int() < avail { len.to_int() } else { avail }
      let result : Array[Byte] = []
      for i = 0; i < to_read; i = i + 1 {
        result.push(self.kernel.stdin_data[self.kernel.stdin_pos + i])
      }
      self.kernel.stdin_pos += to_read
      Ok(Bytes::from_iter(result.iter()))
    }
    Some(FileRead(desc_id, offset)) =>
      match self.kernel.descriptors.get(desc_id) {
        None => Err(stream_closed_error())
        Some(desc) =>
          try {
            let data = self.kernel.fs.read_file(desc.path)
            let start = offset.to_int()
            if start >= data.length() {
              return Ok(b"")
            }
            let avail = data.length() - start
            let to_read = if len.to_int() < avail {
              len.to_int()
            } else {
              avail
            }
            let result : Array[Byte] = []
            for i = 0; i < to_read; i = i + 1 {
              result.push(data[start + i])
            }
            self.kernel.streams[id] = FileRead(
              desc_id,
              offset + to_read.to_uint64(),
            )
            Ok(Bytes::from_iter(result.iter()))
          } catch {
            e => Err(fs_error_to_wasi(e))
          }
      }
    Some(HttpBodyRead(body_id)) =>
      match self.kernel.http_incoming_bodies.get(body_id) {
        None => Err(stream_closed_error())
        Some(body) => {
          let avail = body.data.length() - body.offset
          if avail <= 0 {
            return Ok(b"")
          }
          let to_read = if len.to_int() < avail { len.to_int() } else { avail }
          let result : Array[Byte] = []
          for i = 0; i < to_read; i = i + 1 {
            result.push(body.data[body.offset + i])
          }
          body.offset += to_read
          Ok(Bytes::from_iter(result.iter()))
        }
      }
    Some(_) => Err(stream_closed_error())
  }
}

///|
fn IoAdapter::write_to_stream(
  self : IoAdapter,
  data : Bytes,
) -> Result[Unit, @p2.WasiError] {
  let id = self.current_output_stream
  match self.kernel.streams.get(id) {
    None => Err(stream_closed_error())
    Some(Closed) => Err(stream_closed_error())
    Some(StdoutStream) => {
      for b in data {
        self.kernel.stdout_buf.push(b)
      }
      Ok(())
    }
    Some(StderrStream) => {
      for b in data {
        self.kernel.stderr_buf.push(b)
      }
      Ok(())
    }
    Some(FileWrite(desc_id, offset)) =>
      match self.kernel.descriptors.get(desc_id) {
        None => Err(stream_closed_error())
        Some(desc) =>
          try {
            // Read existing data, expand if needed, write at offset
            let existing = if self.kernel.fs.exists(desc.path) &&
              self.kernel.fs.is_file(desc.path) {
              self.kernel.fs.read_file(desc.path)
            } else {
              b""
            }
            let start = offset.to_int()
            let new_len = if start + data.length() > existing.length() {
              start + data.length()
            } else {
              existing.length()
            }
            let result : Array[Byte] = []
            for i = 0; i < new_len; i = i + 1 {
              if i >= start && i < start + data.length() {
                result.push(data[i - start])
              } else if i < existing.length() {
                result.push(existing[i])
              } else {
                result.push(b'\x00')
              }
            }
            self.kernel.fs.write_file(
              desc.path,
              Bytes::from_iter(result.iter()),
            )
            self.kernel.streams[id] = FileWrite(
              desc_id,
              offset + data.length().to_uint64(),
            )
            Ok(())
          } catch {
            e => Err(fs_error_to_wasi(e))
          }
      }
    Some(HttpBodyWrite(body_id)) =>
      match self.kernel.http_outgoing_bodies.get(body_id) {
        None => Err(stream_closed_error())
        Some(body) => {
          for b in data {
            body.buffer.push(b)
          }
          Ok(())
        }
      }
    Some(FileAppend(desc_id)) =>
      match self.kernel.descriptors.get(desc_id) {
        None => Err(stream_closed_error())
        Some(desc) =>
          try {
            let existing = if self.kernel.fs.exists(desc.path) &&
              self.kernel.fs.is_file(desc.path) {
              self.kernel.fs.read_file(desc.path)
            } else {
              b""
            }
            let result : Array[Byte] = []
            for b in existing {
              result.push(b)
            }
            for b in data {
              result.push(b)
            }
            self.kernel.fs.write_file(
              desc.path,
              Bytes::from_iter(result.iter()),
            )
            Ok(())
          } catch {
            e => Err(fs_error_to_wasi(e))
          }
      }
    Some(_) => Err(stream_closed_error())
  }
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with input_stream_read(
  self,
  len,
) {
  self.read_from_stream(len)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with input_stream_blocking_read(
  self,
  len,
) {
  self.read_from_stream(len)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with input_stream_skip(
  self,
  len,
) {
  match self.read_from_stream(len) {
    Ok(data) => Ok(data.length().to_uint64())
    Err(e) => Err(e)
  }
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with input_stream_blocking_skip(
  self,
  len,
) {
  match self.read_from_stream(len) {
    Ok(data) => Ok(data.length().to_uint64())
    Err(e) => Err(e)
  }
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with input_stream_subscribe(
  self,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.IoPollPollable(id))
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_check_write(
  _self,
) {
  Ok(65536UL)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_write(
  self,
  data,
) {
  self.write_to_stream(data)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_blocking_write_and_flush(
  self,
  data,
) {
  self.write_to_stream(data)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_flush(_self) {
  Ok(())
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_blocking_flush(
  _self,
) {
  Ok(())
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_subscribe(
  self,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.IoPollPollable(id))
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_write_zeroes(
  self,
  len,
) {
  let zeroes = Bytes::make(len.to_int(), b'\x00')
  self.write_to_stream(zeroes)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_blocking_write_zeroes_and_flush(
  self,
  len,
) {
  let zeroes = Bytes::make(len.to_int(), b'\x00')
  self.write_to_stream(zeroes)
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_splice(
  self,
  _src,
  len,
) {
  // Simplified: read from current input, write to current output
  match self.read_from_stream(len) {
    Ok(data) =>
      match self.write_to_stream(data) {
        Ok(_) => Ok(data.length().to_uint64())
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
pub impl @p2.WasiIoStreamsAdapter for IoAdapter with output_stream_blocking_splice(
  self,
  src,
  len,
) {
  (self as &@p2.WasiIoStreamsAdapter).output_stream_splice(src, len)
}

///|
pub impl @p2.WasiIoErrorAdapter for IoAdapter with error_to_debug_string(self) {
  let id = self.current_error
  match self.kernel.errors.get(id) {
    Some(msg) => Ok(msg)
    None => Ok("unknown error")
  }
}

///|
pub impl @p2.WasiIoPollAdapter for IoAdapter with pollable_ready(_self) {
  Ok(true)
}

///|
pub impl @p2.WasiIoPollAdapter for IoAdapter with pollable_block(_self) {
  Ok(())
}

///|
pub impl @p2.WasiIoPollAdapter for IoAdapter with poll(_self, pollables) {
  let result : Array[UInt] = []
  for i = 0; i < pollables.length(); i = i + 1 {
    result.push(i.reinterpret_as_uint())
  }
  Ok(result)
}
