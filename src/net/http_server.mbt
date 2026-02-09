///| Simple HTTP server on virtual network

///|
/// HTTP handler type
pub struct HttpHandler((HttpRequest) -> HttpResponse)

///|
/// Create HTTP handler
pub fn HttpHandler::new(f : (HttpRequest) -> HttpResponse) -> HttpHandler {
  HttpHandler(f)
}

///|
/// HTTP Server
pub struct HttpServer {
  network : VirtualNetwork
  socket : VSocket
  port : Int
  handlers : Map[String, HttpHandler]
}

///|
pub fn HttpServer::new(
  network : VirtualNetwork,
  port : Int,
) -> HttpServer raise NetError {
  let socket = VSocket::new()
  socket.bind(NetAddr::localhost(port))
  socket.listen()
  network.register_listener(socket)
  { network, socket, port, handlers: {} }
}

///|
/// Register a handler for a path
pub fn HttpServer::handle(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.handlers[path] = handler
}

///|
/// Process one request (non-blocking)
pub fn HttpServer::process_one(self : HttpServer) -> Bool {
  // Transfer any pending data
  self.network.transfer()

  // Try to accept a connection
  match self.network.accept(self.socket) {
    Some(client_socket) => {
      // Transfer data to get the request
      self.network.transfer()

      // Read request data
      let data = client_socket.read(65536) catch { _ => return false }
      if data.length() == 0 {
        return false
      }

      // Parse request
      let response = match parse_http_request(data) {
        Some(req) =>
          // Find handler
          match self.handlers.get(req.path) {
            Some(HttpHandler(handler)) => handler(req)
            None => HttpResponse::not_found()
          }
        None => HttpResponse::new(400, "Bad Request")
      }

      // Send response
      let response_bytes = generate_http_response(response)
      try {
        let _ = client_socket.write(response_bytes)

      } catch {
        _ => ()
      }

      // Transfer response to client
      self.network.transfer()
      client_socket.close()
      true
    }
    None => false
  }
}

///|
/// Get the port
pub fn HttpServer::get_port(self : HttpServer) -> Int {
  self.port
}

///|
/// HTTP Client for making requests to virtual servers
pub struct HttpClient {
  network : VirtualNetwork
}

///|
pub fn HttpClient::new(network : VirtualNetwork) -> HttpClient {
  { network, }
}

///|
/// Make a request
pub fn HttpClient::request(
  self : HttpClient,
  addr : NetAddr,
  req : HttpRequest,
) -> HttpResponse raise NetError {
  let socket = VSocket::new()

  // Connect to server
  self.network.connect(socket, addr)

  // Send request
  let request_bytes = generate_http_request(req)
  let _ = socket.write(request_bytes)

  // Transfer data
  self.network.transfer()

  // Wait for response (in real impl, would need to poll)
  // For simulation, transfer handles it
  self.network.transfer()

  // Read response
  let response_data = socket.read(65536)
  socket.close()
  match parse_http_response(response_data) {
    Some(resp) => resp
    None => raise NetError::InvalidState("Invalid HTTP response")
  }
}

///|
/// Convenience method for GET request
pub fn HttpClient::get(
  self : HttpClient,
  addr : NetAddr,
  path : String,
) -> HttpResponse raise NetError {
  let req = HttpRequest::new(HttpMethod::GET, path, [], Bytes::new(0))
  self.request(addr, req)
}

///|
/// Convenience method for POST request
pub fn HttpClient::post(
  self : HttpClient,
  addr : NetAddr,
  path : String,
  body : String,
) -> HttpResponse raise NetError {
  let req = HttpRequest::new(
    HttpMethod::POST,
    path,
    [("Content-Type", "application/json")],
    string_to_bytes(body),
  )
  self.request(addr, req)
}
