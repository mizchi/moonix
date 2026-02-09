///|
pub struct HttpAdapter {
  kernel : Kernel
  mut current_fields : Int
  mut current_request : Int
  mut current_response : Int
}

///|
pub fn HttpAdapter::new(kernel : Kernel) -> HttpAdapter {
  { kernel, current_fields: 0, current_request: 0, current_response: 0 }
}

///|
fn fields_to_pairs(kernel : Kernel, fields_id : Int) -> Array[(String, Bytes)] {
  match kernel.http_fields.get(fields_id) {
    None => []
    Some(fs) => {
      let result : Array[(String, Bytes)] = []
      fs.entries.each(fn(name, values) {
        for v in values {
          result.push((name, v))
        }
      })
      result
    }
  }
}

///|
fn pairs_to_fields(kernel : Kernel, pairs : Array[(String, Bytes)]) -> Int {
  let entries : Map[String, Array[Bytes]] = {}
  for pair in pairs {
    let (name, value) = pair
    match entries.get(name) {
      Some(arr) => arr.push(value)
      None => entries[name] = [value]
    }
  }
  kernel.alloc_fields({ entries, })
}

// ===== Fields =====

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_constructor(self) {
  let id = self.kernel.alloc_fields({ entries: {} })
  self.current_fields = id
  Ok(())
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_from_list(
  self,
  list,
) {
  let entries : Map[String, Array[Bytes]] = {}
  for item in list {
    // Each item is encoded as name_bytes + ":" + value_bytes
    let mut colon_pos = -1
    for i = 0; i < item.length(); i = i + 1 {
      if item[i] == b':' {
        colon_pos = i
        break
      }
    }
    if colon_pos >= 0 {
      let name_arr : Array[Byte] = []
      for i = 0; i < colon_pos; i = i + 1 {
        name_arr.push(item[i])
      }
      let value_arr : Array[Byte] = []
      for i = colon_pos + 1; i < item.length(); i = i + 1 {
        value_arr.push(item[i])
      }
      let name = bytes_to_string(Bytes::from_iter(name_arr.iter()))
      let value = Bytes::from_iter(value_arr.iter())
      match entries.get(name) {
        Some(arr) => arr.push(value)
        None => entries[name] = [value]
      }
    }
  }
  let id = self.kernel.alloc_fields({ entries, })
  self.current_fields = id
  Ok(@p3.HttpTypesFields(id))
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_get(self, name) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok([])
    Some(fs) =>
      match fs.entries.get(name.0) {
        None => Ok([])
        Some(values) => {
          let result : Array[@p3.HttpTypesFieldValue] = []
          for v in values {
            result.push(@p3.HttpTypesFieldValue(v))
          }
          Ok(result)
        }
      }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_has(self, name) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok(false)
    Some(fs) => Ok(fs.entries.contains(name.0))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_set(
  self,
  name,
  values,
) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok(())
    Some(fs) => {
      let arr : Array[Bytes] = []
      for v in values {
        arr.push(v.0)
      }
      fs.entries[name.0] = arr
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_delete(self, name) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok(())
    Some(fs) => {
      fs.entries.remove(name.0)
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_get_and_delete(
  self,
  name,
) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok([])
    Some(fs) =>
      match fs.entries.get(name.0) {
        None => Ok([])
        Some(values) => {
          let result : Array[@p3.HttpTypesFieldValue] = []
          for v in values {
            result.push(@p3.HttpTypesFieldValue(v))
          }
          fs.entries.remove(name.0)
          Ok(result)
        }
      }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_append(
  self,
  name,
  value,
) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok(())
    Some(fs) =>
      match fs.entries.get(name.0) {
        Some(arr) => {
          arr.push(value.0)
          Ok(())
        }
        None => {
          fs.entries[name.0] = [value.0]
          Ok(())
        }
      }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_copy_all(self) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok([])
    Some(fs) => {
      let result : Array[Bytes] = []
      fs.entries.each(fn(name, values) {
        let name_bytes = string_to_bytes(name)
        for v in values {
          let buf : Array[Byte] = []
          for b in name_bytes {
            buf.push(b)
          }
          buf.push(b':')
          for b in v {
            buf.push(b)
          }
          result.push(Bytes::from_iter(buf.iter()))
        }
      })
      Ok(result)
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with fields_clone(self) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => {
      let new_id = self.kernel.alloc_fields({ entries: {} })
      Ok(@p3.HttpTypesFields(new_id))
    }
    Some(fs) => {
      let new_entries : Map[String, Array[Bytes]] = {}
      fs.entries.each(fn(name, values) {
        let cloned : Array[Bytes] = []
        for v in values {
          cloned.push(v)
        }
        new_entries[name] = cloned
      })
      let new_id = self.kernel.alloc_fields({ entries: new_entries })
      Ok(@p3.HttpTypesFields(new_id))
    }
  }
}

// ===== Request =====

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_new(
  self,
  headers,
  body,
  _trailers,
  _options,
) {
  let body_data = match body {
    Some(b) => b
    None => b""
  }
  let req_id = self.kernel.alloc_request({
    method_: "GET",
    path: "/",
    scheme: Some("https"),
    authority: None,
    headers_id: headers.0,
    body: body_data,
  })
  self.current_request = req_id
  // Return request ID encoded as bytes
  let buf : Array[Byte] = []
  buf.push((req_id & 0xFF).to_byte())
  buf.push(((req_id >> 8) & 0xFF).to_byte())
  buf.push(((req_id >> 16) & 0xFF).to_byte())
  buf.push(((req_id >> 24) & 0xFF).to_byte())
  Ok(Bytes::from_iter(buf.iter()))
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_method(self) {
  match self.kernel.http_requests.get(self.current_request) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_get_method"))
    Some(req) => Ok(string_to_method(req.method_))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_set_method(
  self,
  http_method,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_set_method"))
    Some(req) => {
      req.method_ = method_to_string(http_method)
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_path_with_query(
  self,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None =>
      Err(
        @p3.WasiError::NotImplemented("HttpTypes.request_get_path_with_query"),
      )
    Some(req) => Ok(Some(req.path))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_set_path_with_query(
  self,
  path,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None =>
      Err(
        @p3.WasiError::NotImplemented("HttpTypes.request_set_path_with_query"),
      )
    Some(req) => {
      req.path = match path {
        Some(p) => p
        None => "/"
      }
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_scheme(self) {
  match self.kernel.http_requests.get(self.current_request) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_get_scheme"))
    Some(req) =>
      match req.scheme {
        None => Ok(None)
        Some(s) => Ok(Some(string_to_scheme(s)))
      }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_set_scheme(
  self,
  scheme,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_set_scheme"))
    Some(req) => {
      req.scheme = match scheme {
        Some(s) => Some(scheme_to_string(s))
        None => None
      }
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_authority(
  self,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None =>
      Err(@p3.WasiError::NotImplemented("HttpTypes.request_get_authority"))
    Some(req) => Ok(req.authority)
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_set_authority(
  self,
  authority,
) {
  match self.kernel.http_requests.get(self.current_request) {
    None =>
      Err(@p3.WasiError::NotImplemented("HttpTypes.request_set_authority"))
    Some(req) => {
      req.authority = authority
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_options(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_get_headers(self) {
  match self.kernel.http_requests.get(self.current_request) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_get_headers"))
    Some(req) => Ok(@p3.HttpTypesHeaders(req.headers_id))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_consume_body(
  self,
  request,
  _trailers,
) {
  let req_id = request.0
  match self.kernel.http_requests.get(req_id) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.request_consume_body"))
    Some(req) => Ok(req.body)
  }
}

// ===== Request Options =====

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_constructor(
  _self,
) {
  Ok(())
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_get_connect_timeout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_set_connect_timeout(
  _self,
  _timeout,
) {
  Ok(())
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_get_first_byte_timeout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_set_first_byte_timeout(
  _self,
  _timeout,
) {
  Ok(())
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_get_between_bytes_timeout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_set_between_bytes_timeout(
  _self,
  _timeout,
) {
  Ok(())
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with request_options_clone(
  _self,
) {
  Ok(@p3.HttpTypesRequestOptions(0))
}

// ===== Response =====

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with response_new(
  self,
  headers,
  body,
  _trailers,
) {
  let body_data = match body {
    Some(b) => b
    None => b""
  }
  let resp_id = self.kernel.alloc_response({
    status: 200,
    headers_id: headers.0,
    body: body_data,
  })
  self.current_response = resp_id
  let buf : Array[Byte] = []
  buf.push((resp_id & 0xFF).to_byte())
  buf.push(((resp_id >> 8) & 0xFF).to_byte())
  buf.push(((resp_id >> 16) & 0xFF).to_byte())
  buf.push(((resp_id >> 24) & 0xFF).to_byte())
  Ok(Bytes::from_iter(buf.iter()))
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with response_get_status_code(
  self,
) {
  match self.kernel.http_responses.get(self.current_response) {
    None =>
      Err(@p3.WasiError::NotImplemented("HttpTypes.response_get_status_code"))
    Some(resp) => Ok(@p3.HttpTypesStatusCode(resp.status))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with response_set_status_code(
  self,
  status,
) {
  match self.kernel.http_responses.get(self.current_response) {
    None =>
      Err(@p3.WasiError::NotImplemented("HttpTypes.response_set_status_code"))
    Some(resp) => {
      resp.status = status.0
      Ok(())
    }
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with response_get_headers(
  self,
) {
  match self.kernel.http_responses.get(self.current_response) {
    None => Err(@p3.WasiError::NotImplemented("HttpTypes.response_get_headers"))
    Some(resp) => Ok(@p3.HttpTypesHeaders(resp.headers_id))
  }
}

///|
pub impl @p3.WasiHttpTypesAdapter for HttpAdapter with response_consume_body(
  self,
  response,
  _trailers,
) {
  let resp_id = response.0
  match self.kernel.http_responses.get(resp_id) {
    None =>
      Err(@p3.WasiError::NotImplemented("HttpTypes.response_consume_body"))
    Some(resp) => Ok(resp.body)
  }
}

// ===== Client =====

///|
pub impl @p3.WasiHttpClientAdapter for HttpAdapter with send(self, request) {
  let req_id = request.0
  match self.kernel.http_requests.get(req_id) {
    None => Err(@p3.WasiError::NotImplemented("HttpClient.send"))
    Some(req) => {
      let headers = fields_to_pairs(self.kernel, req.headers_id)
      let (status, resp_headers, resp_body) = match
        self.kernel.http_mock_handler {
        None => (404, ([] : Array[(String, Bytes)]), b"")
        Some(handler) => handler(req.method_, req.path, headers, req.body)
      }
      let resp_fields_id = pairs_to_fields(self.kernel, resp_headers)
      let resp_id = self.kernel.alloc_response({
        status,
        headers_id: resp_fields_id,
        body: resp_body,
      })
      self.current_response = resp_id
      Ok(@p3.HttpTypesResponse(resp_id))
    }
  }
}

// ===== Handler =====

///|
pub impl @p3.WasiHttpHandlerAdapter for HttpAdapter with handle(_self, _request) {
  Ok(
    // Server-side handler - return a default 200 response
    @p3.HttpTypesResponse(0),
  )
}

// ===== Helper functions =====

///|
fn string_to_method(s : String) -> @p3.HttpTypesMethod {
  match s {
    "GET" => @p3.HttpTypesMethod::Get
    "HEAD" => @p3.HttpTypesMethod::Head
    "POST" => @p3.HttpTypesMethod::Post
    "PUT" => @p3.HttpTypesMethod::Put
    "DELETE" => @p3.HttpTypesMethod::Delete
    "CONNECT" => @p3.HttpTypesMethod::Connect
    "OPTIONS" => @p3.HttpTypesMethod::Options
    "TRACE" => @p3.HttpTypesMethod::Trace
    "PATCH" => @p3.HttpTypesMethod::Patch
    _ => @p3.HttpTypesMethod::Other(s)
  }
}

///|
fn method_to_string(m : @p3.HttpTypesMethod) -> String {
  match m {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
    Other(s) => s
  }
}

///|
fn string_to_scheme(s : String) -> @p3.HttpTypesScheme {
  match s {
    "http" => @p3.HttpTypesScheme::Http
    "https" => @p3.HttpTypesScheme::Https
    _ => @p3.HttpTypesScheme::Other(s)
  }
}

///|
fn scheme_to_string(s : @p3.HttpTypesScheme) -> String {
  match s {
    Http => "http"
    Https => "https"
    Other(v) => v
  }
}

///|
fn bytes_to_string(b : Bytes) -> String {
  let arr : Array[Char] = []
  for i = 0; i < b.length(); i = i + 1 {
    arr.push(b[i].to_int().unsafe_to_char())
  }
  String::from_array(arr)
}
