///| HTTP parsing and generation

/// Parse HTTP request from bytes
pub fn parse_http_request(data : Bytes) -> HttpRequest? {
  let s = bytes_to_string(data)
  let lines = split_lines(s)

  if lines.length() == 0 {
    return None
  }

  // Parse request line: METHOD PATH HTTP/1.1
  let request_line = lines[0]
  let parts = split_spaces(request_line)
  if parts.length() < 2 {
    return None
  }

  let http_method = match HttpMethod::from_string(parts[0]) {
    Some(m) => m
    None => return None
  }
  let path = parts[1]

  // Parse headers
  let headers : Array[(String, String)] = []
  let mut body_start = 0
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.length() == 0 {
      body_start = i + 1
      break
    }
    let colon_pos = find_char(line, ':')
    match colon_pos {
      Some(pos) => {
        let name = substring(line, 0, pos)
        let value = trim(substring(line, pos + 1, line.length()))
        headers.push((name, value))
      }
      None => ()
    }
  }

  // Parse body
  let body = if body_start > 0 && body_start < lines.length() {
    let body_str = StringBuilder::new()
    for i = body_start; i < lines.length(); i = i + 1 {
      if i > body_start {
        body_str.write_char('\n')
      }
      body_str.write_string(lines[i])
    }
    string_to_bytes(body_str.to_string())
  } else {
    Bytes::new(0)
  }

  Some(HttpRequest::new(http_method, path, headers, body))
}

/// Generate HTTP response bytes
pub fn generate_http_response(resp : HttpResponse) -> Bytes {
  let buf = StringBuilder::new()

  // Status line
  buf.write_string("HTTP/1.1 ")
  buf.write_string(resp.status.to_string())
  buf.write_string(" ")
  buf.write_string(resp.status_text)
  buf.write_string("\r\n")

  // Add Content-Length if body exists
  if resp.body.length() > 0 {
    buf.write_string("Content-Length: ")
    buf.write_string(resp.body.length().to_string())
    buf.write_string("\r\n")
  }

  // Headers
  for header in resp.headers {
    buf.write_string(header.0)
    buf.write_string(": ")
    buf.write_string(header.1)
    buf.write_string("\r\n")
  }

  // Empty line
  buf.write_string("\r\n")

  // Concatenate header and body
  concat_bytes(string_to_bytes(buf.to_string()), resp.body)
}

/// Generate HTTP request bytes
pub fn generate_http_request(req : HttpRequest) -> Bytes {
  let buf = StringBuilder::new()

  // Request line
  buf.write_string(req.http_method.to_string())
  buf.write_string(" ")
  buf.write_string(req.path)
  buf.write_string(" HTTP/1.1\r\n")

  // Add Content-Length if body exists
  if req.body.length() > 0 {
    buf.write_string("Content-Length: ")
    buf.write_string(req.body.length().to_string())
    buf.write_string("\r\n")
  }

  // Headers
  for header in req.headers {
    buf.write_string(header.0)
    buf.write_string(": ")
    buf.write_string(header.1)
    buf.write_string("\r\n")
  }

  // Empty line
  buf.write_string("\r\n")

  // Concatenate header and body
  concat_bytes(string_to_bytes(buf.to_string()), req.body)
}

/// Parse HTTP response from bytes
pub fn parse_http_response(data : Bytes) -> HttpResponse? {
  let s = bytes_to_string(data)
  let lines = split_lines(s)

  if lines.length() == 0 {
    return None
  }

  // Parse status line: HTTP/1.1 200 OK
  let status_line = lines[0]
  let parts = split_spaces(status_line)
  if parts.length() < 2 {
    return None
  }

  let status = match parse_int(parts[1]) {
    Some(n) => n
    None => return None
  }
  let status_text = if parts.length() > 2 { parts[2] } else { "" }

  // Parse headers
  let headers : Array[(String, String)] = []
  let mut body_start = 0
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.length() == 0 {
      body_start = i + 1
      break
    }
    let colon_pos = find_char(line, ':')
    match colon_pos {
      Some(pos) => {
        let name = substring(line, 0, pos)
        let value = trim(substring(line, pos + 1, line.length()))
        headers.push((name, value))
      }
      None => ()
    }
  }

  // Parse body
  let body = if body_start > 0 && body_start < lines.length() {
    let body_str = StringBuilder::new()
    for i = body_start; i < lines.length(); i = i + 1 {
      if i > body_start {
        body_str.write_char('\n')
      }
      body_str.write_string(lines[i])
    }
    string_to_bytes(body_str.to_string())
  } else {
    Bytes::new(0)
  }

  Some({ status, status_text, headers, body })
}

// Helper functions

fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  if b.length() == 0 {
    return a
  }
  Bytes::makei(a.length() + b.length(), fn(i) {
    if i < a.length() { a[i] } else { b[i - a.length()] }
  })
}

fn bytes_to_string(b : Bytes) -> String {
  let buf = StringBuilder::new()
  for byte in b {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn string_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}

fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current = StringBuilder::new()
  let mut prev_cr = false

  for c in s {
    if c == '\r' {
      prev_cr = true
    } else if c == '\n' {
      lines.push(current.to_string())
      current.reset()
      prev_cr = false
    } else {
      if prev_cr {
        current.write_char('\r')
        prev_cr = false
      }
      current.write_char(c)
    }
  }

  if current.to_string().length() > 0 {
    lines.push(current.to_string())
  }

  lines
}

fn split_spaces(s : String) -> Array[String] {
  let parts : Array[String] = []
  let current = StringBuilder::new()

  for c in s {
    if c == ' ' {
      if current.to_string().length() > 0 {
        parts.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
    }
  }

  if current.to_string().length() > 0 {
    parts.push(current.to_string())
  }

  parts
}

fn find_char(s : String, target : Char) -> Int? {
  let target_code = target.to_int()
  for i, c in s {
    if c.to_int() == target_code {
      return Some(i)
    }
  }
  None
}

fn substring(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let mut idx = 0
  for c in s {
    if idx >= start && idx < end {
      buf.write_char(c)
    }
    idx += 1
  }
  buf.to_string()
}

fn trim(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }

  let mut start = 0
  let mut end = chars.length()

  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start += 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end -= 1
  }

  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

fn parse_int(s : String) -> Int? {
  let mut result = 0
  let mut has_digit = false

  for c in s {
    let code = c.to_int()
    if code >= 48 && code <= 57 {
      result = result * 10 + (code - 48)
      has_digit = true
    } else {
      break
    }
  }

  if has_digit { Some(result) } else { None }
}
