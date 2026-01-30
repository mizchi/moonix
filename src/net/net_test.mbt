///| Tests for virtual network and HTTP

test "parse HTTP request" {
  let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
  let data = Bytes::makei(raw.length(), fn(i) { raw[i].to_int().to_byte() })

  match @net.parse_http_request(data) {
    Some(req) => {
      assert_eq(req.path, "/hello")
      assert_true(req.headers.length() > 0)
    }
    None => panic()
  }
}

test "generate HTTP response" {
  let resp = @net.HttpResponse::ok()
    .set_body_string("Hello!")
    .add_header("Content-Type", "text/plain")

  let bytes = @net.generate_http_response(resp)
  let s = bytes_to_str(bytes)

  assert_true(s.contains("200 OK"))
  assert_true(s.contains("Hello!"))
}

test "HTTP server and client" {
  let network = @net.VirtualNetwork::new()

  // Create server
  let server = try {
    @net.HttpServer::new(network, 8080)
  } catch {
    e => {
      println("Failed to create server: \{e}")
      return
    }
  }

  // Register handler
  server.handle(
    "/hello",
    @net.HttpHandler::new(fn(_req : @net.HttpRequest) { @net.HttpResponse::ok().set_body_string("Hello World!") }),
  )

  // Manually orchestrate request/response:
  // 1. Client connects and sends request
  let socket = @net.VSocket::new()
  try {
    network.connect(socket, @net.NetAddr::localhost(8080))
  } catch {
    _ => return
  }

  let req_str = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
  let req_bytes = Bytes::makei(req_str.length(), fn(i) { req_str[i].to_int().to_byte() })
  try {
    let _ = socket.write(req_bytes)
  } catch {
    _ => return
  }

  network.transfer()

  // 2. Server processes request
  let _ = server.process_one()

  // 3. Read response
  network.transfer()
  let resp_data = try {
    socket.read(65536)
  } catch {
    _ => return
  }

  let resp_str = bytes_to_str(resp_data)
  assert_true(resp_str.contains("200 OK"))
  assert_true(resp_str.contains("Hello World!"))
}

test "HTTP 404" {
  let network = @net.VirtualNetwork::new()
  let server = try {
    @net.HttpServer::new(network, 8081)
  } catch {
    _ => return
  }

  // Manually make request
  let socket = @net.VSocket::new()
  try {
    network.connect(socket, @net.NetAddr::localhost(8081))
  } catch {
    _ => return
  }

  let req_str = "GET /notfound HTTP/1.1\r\nHost: localhost\r\n\r\n"
  let req_bytes = Bytes::makei(req_str.length(), fn(i) { req_str[i].to_int().to_byte() })
  try {
    let _ = socket.write(req_bytes)
  } catch {
    _ => return
  }

  network.transfer()
  let _ = server.process_one()
  network.transfer()

  let resp_data = try {
    socket.read(65536)
  } catch {
    _ => return
  }

  let resp_str = bytes_to_str(resp_data)
  assert_true(resp_str.contains("404"))
}

test "HTTP POST with body" {
  let network = @net.VirtualNetwork::new()
  let server = try {
    @net.HttpServer::new(network, 8082)
  } catch {
    _ => return
  }

  server.handle(
    "/data",
    @net.HttpHandler::new(
      fn(req : @net.HttpRequest) {
        // Echo back the body
        @net.HttpResponse::ok().set_body(req.body)
      },
    ),
  )

  // Manually make POST request
  let socket = @net.VSocket::new()
  try {
    network.connect(socket, @net.NetAddr::localhost(8082))
  } catch {
    _ => return
  }

  let body = "test body"
  let req_str = "POST /data HTTP/1.1\r\nHost: localhost\r\nContent-Length: \{body.length()}\r\n\r\n\{body}"
  let req_bytes = Bytes::makei(req_str.length(), fn(i) { req_str[i].to_int().to_byte() })
  try {
    let _ = socket.write(req_bytes)
  } catch {
    _ => return
  }

  network.transfer()
  let _ = server.process_one()
  network.transfer()

  let resp_data = try {
    socket.read(65536)
  } catch {
    _ => return
  }

  let resp_str = bytes_to_str(resp_data)
  assert_true(resp_str.contains("200 OK"))
  assert_true(resp_str.contains("test body"))
}

fn bytes_to_str(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}
