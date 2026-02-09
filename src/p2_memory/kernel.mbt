///|
pub enum StreamState {
  StdinStream
  StdoutStream
  StderrStream
  FileRead(Int, UInt64) // descriptor_id, offset
  FileWrite(Int, UInt64) // descriptor_id, offset
  FileAppend(Int) // descriptor_id
  HttpBodyRead(Int) // incoming_body_id
  HttpBodyWrite(Int) // outgoing_body_id
  Closed
}

///|
pub struct DescriptorState {
  path : String
  type_ : @p2.FilesystemTypesDescriptorType
}

///|
pub struct DirStreamState {
  entries : Array[@p2.FilesystemTypesDirectoryEntry]
  mut cursor : Int
}

///|
pub struct HttpFieldsState {
  entries : Map[String, Array[Bytes]]
}

///|
pub struct HttpOutgoingRequestState {
  headers_id : Int
  method_ : String
  path : String
  scheme : String?
  authority : String?
  mut body_id : Int?
}

///|
pub struct HttpIncomingResponseState {
  status : Int
  headers_id : Int
  body_data : Bytes
}

///|
pub struct HttpOutgoingBodyState {
  buffer : Array[Byte]
  mut stream_id : Int?
}

///|
pub struct HttpIncomingBodyState {
  data : Bytes
  mut offset : Int
  stream_id : Int?
}

///|
pub struct HttpFutureIncomingResponseState {
  response_id : Int?
}

///|
pub struct HttpOutgoingResponseState {
  headers_id : Int
  status : Int
  mut body_id : Int?
}

///|
pub struct HttpIncomingRequestState {
  method_ : String
  path : String
  scheme : String?
  authority : String?
  headers_id : Int
  body_data : Bytes
}

///|
pub struct Kernel {
  fs : @fs.MemFs
  streams : Map[Int, StreamState]
  mut next_stream_id : Int
  descriptors : Map[Int, DescriptorState]
  mut next_descriptor_id : Int
  dir_streams : Map[Int, DirStreamState]
  mut next_dir_stream_id : Int
  errors : Map[Int, String]
  mut next_error_id : Int
  pollables : Map[Int, Bool]
  mut next_pollable_id : Int
  stdin_data : Bytes
  mut stdin_pos : Int
  stdout_buf : Array[Byte]
  stderr_buf : Array[Byte]
  env : Map[String, String]
  args : Array[String]
  cwd : String
  wall_seconds : UInt64
  wall_nanoseconds : UInt
  monotonic_ns : UInt64
  mut prng_state : UInt64
  mut exit_code : Int?
  preopens : Array[String]
  // HTTP state tables
  http_fields : Map[Int, HttpFieldsState]
  mut next_fields_id : Int
  http_outgoing_requests : Map[Int, HttpOutgoingRequestState]
  mut next_outgoing_request_id : Int
  http_incoming_responses : Map[Int, HttpIncomingResponseState]
  mut next_incoming_response_id : Int
  http_outgoing_bodies : Map[Int, HttpOutgoingBodyState]
  mut next_outgoing_body_id : Int
  http_incoming_bodies : Map[Int, HttpIncomingBodyState]
  mut next_incoming_body_id : Int
  http_futures : Map[Int, HttpFutureIncomingResponseState]
  mut next_future_id : Int
  http_outgoing_responses : Map[Int, HttpOutgoingResponseState]
  mut next_outgoing_response_id : Int
  http_incoming_requests : Map[Int, HttpIncomingRequestState]
  mut next_incoming_request_id : Int
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
  let streams : Map[Int, StreamState] = {}
  streams[0] = StdinStream
  streams[1] = StdoutStream
  streams[2] = StderrStream
  let descriptors : Map[Int, DescriptorState] = {}
  for i, path in preopens {
    descriptors[i] = { path, type_: Directory }
  }
  {
    fs,
    streams,
    next_stream_id: 3,
    descriptors,
    next_descriptor_id: preopens.length(),
    dir_streams: {},
    next_dir_stream_id: 0,
    errors: {},
    next_error_id: 0,
    pollables: {},
    next_pollable_id: 0,
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
    http_fields: {},
    next_fields_id: 0,
    http_outgoing_requests: {},
    next_outgoing_request_id: 0,
    http_incoming_responses: {},
    next_incoming_response_id: 0,
    http_outgoing_bodies: {},
    next_outgoing_body_id: 0,
    http_incoming_bodies: {},
    next_incoming_body_id: 0,
    http_futures: {},
    next_future_id: 0,
    http_outgoing_responses: {},
    next_outgoing_response_id: 0,
    http_incoming_requests: {},
    next_incoming_request_id: 0,
    http_mock_handler: None,
  }
}

///|
pub fn Kernel::alloc_stream(self : Kernel, state : StreamState) -> Int {
  let id = self.next_stream_id
  self.next_stream_id += 1
  self.streams[id] = state
  id
}

///|
pub fn Kernel::alloc_descriptor(self : Kernel, state : DescriptorState) -> Int {
  let id = self.next_descriptor_id
  self.next_descriptor_id += 1
  self.descriptors[id] = state
  id
}

///|
pub fn Kernel::alloc_dir_stream(self : Kernel, state : DirStreamState) -> Int {
  let id = self.next_dir_stream_id
  self.next_dir_stream_id += 1
  self.dir_streams[id] = state
  id
}

///|
pub fn Kernel::alloc_error(self : Kernel, msg : String) -> Int {
  let id = self.next_error_id
  self.next_error_id += 1
  self.errors[id] = msg
  id
}

///|
pub fn Kernel::alloc_pollable(self : Kernel) -> Int {
  let id = self.next_pollable_id
  self.next_pollable_id += 1
  self.pollables[id] = true
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
pub fn Kernel::alloc_outgoing_request(
  self : Kernel,
  state : HttpOutgoingRequestState,
) -> Int {
  let id = self.next_outgoing_request_id
  self.next_outgoing_request_id += 1
  self.http_outgoing_requests[id] = state
  id
}

///|
pub fn Kernel::alloc_incoming_response(
  self : Kernel,
  state : HttpIncomingResponseState,
) -> Int {
  let id = self.next_incoming_response_id
  self.next_incoming_response_id += 1
  self.http_incoming_responses[id] = state
  id
}

///|
pub fn Kernel::alloc_outgoing_body(
  self : Kernel,
  state : HttpOutgoingBodyState,
) -> Int {
  let id = self.next_outgoing_body_id
  self.next_outgoing_body_id += 1
  self.http_outgoing_bodies[id] = state
  id
}

///|
pub fn Kernel::alloc_incoming_body(
  self : Kernel,
  state : HttpIncomingBodyState,
) -> Int {
  let id = self.next_incoming_body_id
  self.next_incoming_body_id += 1
  self.http_incoming_bodies[id] = state
  id
}

///|
pub fn Kernel::alloc_future(
  self : Kernel,
  state : HttpFutureIncomingResponseState,
) -> Int {
  let id = self.next_future_id
  self.next_future_id += 1
  self.http_futures[id] = state
  id
}

///|
pub fn Kernel::alloc_outgoing_response(
  self : Kernel,
  state : HttpOutgoingResponseState,
) -> Int {
  let id = self.next_outgoing_response_id
  self.next_outgoing_response_id += 1
  self.http_outgoing_responses[id] = state
  id
}

///|
pub fn Kernel::alloc_incoming_request(
  self : Kernel,
  state : HttpIncomingRequestState,
) -> Int {
  let id = self.next_incoming_request_id
  self.next_incoming_request_id += 1
  self.http_incoming_requests[id] = state
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
pub fn fs_error_to_wasi(err : @fs.FsError) -> @p2.WasiError {
  match err {
    NotFound(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::NoEntry,
      )
    AlreadyExists(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::Exist,
      )
    NotADirectory(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::NotDirectory,
      )
    NotAFile(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::IsDirectory,
      )
    IsADirectory(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::IsDirectory,
      )
    NotEmpty(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::NotEmpty,
      )
    PermissionDenied(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::Access,
      )
    InvalidPath(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::Invalid,
      )
    IoError(_) =>
      @p2.WasiError::FromFilesystemtypeserrorcode(
        @p2.FilesystemTypesErrorCode::Io,
      )
  }
}

///|
pub fn stream_closed_error() -> @p2.WasiError {
  @p2.WasiError::FromIostreamsstreamerror(@p2.IoStreamsStreamError::Closed)
}
