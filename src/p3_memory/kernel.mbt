///|
pub struct DescriptorState {
  path : String
  type_ : @p3.FilesystemTypesDescriptorType
}

///|
pub struct HttpFieldsState {
  entries : Map[String, Array[Bytes]]
}

///|
pub struct HttpRequestState {
  mut method_ : String
  mut path : String
  mut scheme : String?
  mut authority : String?
  headers_id : Int
  body : Bytes
}

///|
pub struct HttpResponseState {
  mut status : Int
  headers_id : Int
  body : Bytes
}

///|
pub struct Kernel {
  fs : @fs.MemFs
  // CLI
  stdin_data : Bytes
  mut stdin_pos : Int
  stdout_buf : Array[Byte]
  stderr_buf : Array[Byte]
  env : Map[String, String]
  args : Array[String]
  cwd : String
  // Clocks
  wall_seconds : UInt64
  wall_nanoseconds : UInt
  monotonic_ns : UInt64
  // Random
  mut prng_state : UInt64
  // Exit
  mut exit_code : Int?
  // Filesystem
  preopens : Array[String]
  descriptors : Map[Int, DescriptorState]
  mut next_descriptor_id : Int
  // HTTP
  http_fields : Map[Int, HttpFieldsState]
  mut next_fields_id : Int
  http_requests : Map[Int, HttpRequestState]
  mut next_request_id : Int
  http_responses : Map[Int, HttpResponseState]
  mut next_response_id : Int
  mut http_mock_handler : ((String, String, Array[(String, Bytes)], Bytes) -> (
    Int,
    Array[(String, Bytes)],
    Bytes,
  ))?
}

///|
pub fn Kernel::new(
  fs : @fs.MemFs,
  stdin? : Bytes = b"",
  env? : Map[String, String] = {},
  args? : Array[String] = [],
  cwd? : String = "/",
  prng_seed? : UInt64 = 42UL,
  wall_seconds? : UInt64 = 1700000000UL,
  wall_nanoseconds? : UInt = 0,
  preopens? : Array[String] = ["/"],
) -> Kernel {
  let descriptors : Map[Int, DescriptorState] = {}
  for i, path in preopens {
    descriptors[i] = { path, type_: Directory }
  }
  {
    fs,
    stdin_data: stdin,
    stdin_pos: 0,
    stdout_buf: [],
    stderr_buf: [],
    env,
    args,
    cwd,
    wall_seconds,
    wall_nanoseconds,
    monotonic_ns: 0UL,
    prng_state: prng_seed,
    exit_code: None,
    preopens,
    descriptors,
    next_descriptor_id: preopens.length(),
    http_fields: {},
    next_fields_id: 0,
    http_requests: {},
    next_request_id: 0,
    http_responses: {},
    next_response_id: 0,
    http_mock_handler: None,
  }
}

///|
pub fn Kernel::alloc_descriptor(self : Kernel, state : DescriptorState) -> Int {
  let id = self.next_descriptor_id
  self.next_descriptor_id += 1
  self.descriptors[id] = state
  id
}

///|
pub fn Kernel::alloc_fields(self : Kernel, state : HttpFieldsState) -> Int {
  let id = self.next_fields_id
  self.next_fields_id += 1
  self.http_fields[id] = state
  id
}

///|
pub fn Kernel::alloc_request(self : Kernel, state : HttpRequestState) -> Int {
  let id = self.next_request_id
  self.next_request_id += 1
  self.http_requests[id] = state
  id
}

///|
pub fn Kernel::alloc_response(self : Kernel, state : HttpResponseState) -> Int {
  let id = self.next_response_id
  self.next_response_id += 1
  self.http_responses[id] = state
  id
}

///|
pub fn Kernel::next_random_u64(self : Kernel) -> UInt64 {
  self.prng_state = xorshift64(self.prng_state)
  self.prng_state
}

///|
pub fn Kernel::next_random_bytes(self : Kernel, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut remaining = len
  while remaining > 0 {
    let val = self.next_random_u64()
    let mut j = 0
    while j < 8 && remaining > 0 {
      arr.push((val >> (j * 8)).to_byte())
      remaining -= 1
      j += 1
    }
  }
  Bytes::from_iter(arr.iter())
}

///|
pub fn Kernel::get_stdout_bytes(self : Kernel) -> Bytes {
  Bytes::from_iter(self.stdout_buf.iter())
}

///|
pub fn Kernel::get_stderr_bytes(self : Kernel) -> Bytes {
  Bytes::from_iter(self.stderr_buf.iter())
}

///|
fn xorshift64(state : UInt64) -> UInt64 {
  let mut s = state
  s = s ^ (s << 13)
  s = s ^ (s >> 7)
  s = s ^ (s << 17)
  s
}

///|
pub fn fs_error_to_wasi(err : @fs.FsError) -> @p3.WasiError {
  match err {
    NotFound(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::NoEntry,
      )
    AlreadyExists(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::Exist,
      )
    NotADirectory(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::NotDirectory,
      )
    NotAFile(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::IsDirectory,
      )
    IsADirectory(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::IsDirectory,
      )
    NotEmpty(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::NotEmpty,
      )
    PermissionDenied(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::Access,
      )
    InvalidPath(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::Invalid,
      )
    IoError(_) =>
      @p3.WasiError::FromFilesystemtypeserrorcode(
        @p3.FilesystemTypesErrorCode::Io,
      )
  }
}
