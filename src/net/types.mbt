///| Virtual network types for socket emulation

///|
/// Network address
pub struct NetAddr {
  host : String
  port : Int
}

///|
pub fn NetAddr::new(host : String, port : Int) -> NetAddr {
  { host, port }
}

///|
pub fn NetAddr::localhost(port : Int) -> NetAddr {
  { host: "127.0.0.1", port }
}

///|
pub impl Show for NetAddr with output(self, logger) {
  logger.write_string(self.host)
  logger.write_string(":")
  logger.write_string(self.port.to_string())
}

///|
/// Socket state
pub enum SocketState {
  Created
  Bound
  Listening
  Connected
  Closed
}

///|
/// Network errors
pub suberror NetError {
  AddressInUse(String)
  ConnectionRefused(String)
  NotConnected
  NotBound
  InvalidState(String)
  Timeout
  Closed
}

///|
pub impl Show for NetError with output(self, logger) {
  match self {
    AddressInUse(msg) => logger.write_string("AddressInUse(\{msg})")
    ConnectionRefused(msg) => logger.write_string("ConnectionRefused(\{msg})")
    NotConnected => logger.write_string("NotConnected")
    NotBound => logger.write_string("NotBound")
    InvalidState(msg) => logger.write_string("InvalidState(\{msg})")
    Timeout => logger.write_string("Timeout")
    Closed => logger.write_string("Closed")
  }
}

///|
/// HTTP Method
pub enum HttpMethod {
  GET
  POST
  PUT
  DELETE
  HEAD
  OPTIONS
  PATCH
}

///|
pub fn HttpMethod::from_string(s : String) -> HttpMethod? {
  match s {
    "GET" => Some(GET)
    "POST" => Some(POST)
    "PUT" => Some(PUT)
    "DELETE" => Some(DELETE)
    "HEAD" => Some(HEAD)
    "OPTIONS" => Some(OPTIONS)
    "PATCH" => Some(PATCH)
    _ => None
  }
}

///|
pub impl Show for HttpMethod with output(self, logger) {
  let s = match self {
    GET => "GET"
    POST => "POST"
    PUT => "PUT"
    DELETE => "DELETE"
    HEAD => "HEAD"
    OPTIONS => "OPTIONS"
    PATCH => "PATCH"
  }
  logger.write_string(s)
}

///|
/// HTTP Request
pub struct HttpRequest {
  http_method : HttpMethod
  path : String
  headers : Array[(String, String)]
  body : Bytes
}

///|
pub fn HttpRequest::new(
  http_method : HttpMethod,
  path : String,
  headers : Array[(String, String)],
  body : Bytes,
) -> HttpRequest {
  { http_method, path, headers, body }
}

///|
pub fn HttpRequest::get_method(self : HttpRequest) -> HttpMethod {
  self.http_method
}

///|
/// HTTP Response
pub struct HttpResponse {
  status : Int
  status_text : String
  headers : Array[(String, String)]
  body : Bytes
}

///|
pub fn HttpResponse::new(status : Int, status_text : String) -> HttpResponse {
  { status, status_text, headers: [], body: Bytes::new(0) }
}

///|
pub fn HttpResponse::ok() -> HttpResponse {
  { status: 200, status_text: "OK", headers: [], body: Bytes::new(0) }
}

///|
pub fn HttpResponse::not_found() -> HttpResponse {
  { status: 404, status_text: "Not Found", headers: [], body: Bytes::new(0) }
}

///|
pub fn HttpResponse::set_body(
  self : HttpResponse,
  body : Bytes,
) -> HttpResponse {
  { ..self, body, }
}

///|
pub fn HttpResponse::set_body_string(
  self : HttpResponse,
  body : String,
) -> HttpResponse {
  let bytes = Bytes::makei(body.length(), fn(i) { body[i].to_int().to_byte() })
  { ..self, body: bytes }
}

///|
pub fn HttpResponse::add_header(
  self : HttpResponse,
  name : String,
  value : String,
) -> HttpResponse {
  let headers = self.headers.copy()
  headers.push((name, value))
  { ..self, headers, }
}
