///|
pub struct HttpAdapter {
  kernel : Kernel
  mut current_fields : Int
  mut current_outgoing_request : Int
  mut current_incoming_response : Int
  current_incoming_request : Int
  mut current_outgoing_response : Int
  mut current_outgoing_body : Int
  mut current_incoming_body : Int
  mut current_future : Int
  current_response_outparam : Int
}

///|
pub fn HttpAdapter::new(kernel : Kernel) -> HttpAdapter {
  {
    kernel,
    current_fields: 0,
    current_outgoing_request: 0,
    current_incoming_response: 0,
    current_incoming_request: 0,
    current_outgoing_response: 0,
    current_outgoing_body: 0,
    current_incoming_body: 0,
    current_future: 0,
    current_response_outparam: 0,
  }
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
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_constructor(self) {
  let id = self.kernel.alloc_fields({ entries: {} })
  self.current_fields = id
  Ok(())
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_get(self, name) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok([])
    Some(fs) =>
      match fs.entries.get(name.0) {
        None => Ok([])
        Some(values) => {
          let result : Array[@p2.HttpTypesFieldValue] = []
          for v in values {
            result.push(@p2.HttpTypesFieldValue(v))
          }
          Ok(result)
        }
      }
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_has(self, name) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok(false)
    Some(fs) => Ok(fs.entries.contains(name.0))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_set(
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
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_delete(self, name) {
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
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_append(
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
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_entries(self) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => Ok([])
    Some(fs) => {
      let result : Array[Bytes] = []
      fs.entries.each(fn(name, values) {
        let name_bytes = string_to_bytes(name)
        for v in values {
          // encode as: name_bytes + b":" + value_bytes
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
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with fields_clone(self) {
  let id = self.current_fields
  match self.kernel.http_fields.get(id) {
    None => {
      let new_id = self.kernel.alloc_fields({ entries: {} })
      Ok(@p2.HttpTypesFields(new_id))
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
      Ok(@p2.HttpTypesFields(new_id))
    }
  }
}

// ===== Outgoing Request =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_constructor(
  self,
  headers,
) {
  let id = self.kernel.alloc_outgoing_request({
    headers_id: headers.0,
    method_: "GET",
    path: "/",
    scheme: Some("https"),
    authority: None,
    body_id: None,
  })
  self.current_outgoing_request = id
  Ok(())
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_body(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) => {
      let body_id = self.kernel.alloc_outgoing_body({
        buffer: [],
        stream_id: None,
      })
      req.body_id = Some(body_id)
      self.current_outgoing_body = body_id
      Ok(@p2.HttpTypesOutgoingBody(body_id))
    }
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_method(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(string_to_method(req.method_))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_path_with_query(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(Some(req.path))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_scheme(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) =>
      match req.scheme {
        None => Ok(None)
        Some(s) => Ok(Some(string_to_scheme(s)))
      }
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_authority(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(req.authority)
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_request_headers(
  self,
) {
  let req_id = self.current_outgoing_request
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(@p2.HttpTypesHeaders(req.headers_id))
  }
}

// ===== Request Options (simplified) =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with request_options_constructor(
  _self,
) {
  Ok(())
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with request_options_connect_timeout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with request_options_first_byte_timeout(
  _self,
) {
  Ok(None)
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with request_options_between_bytes_timeout(
  _self,
) {
  Ok(None)
}

// ===== Response Outparam =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with response_outparam_send_informational(
  _self,
  _status,
  _headers,
) {
  Ok(())
}

// ===== Incoming Response =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_response_status(
  self,
) {
  let resp_id = self.current_incoming_response
  match self.kernel.http_incoming_responses.get(resp_id) {
    None => Err(stream_closed_error())
    Some(resp) => Ok(@p2.HttpTypesStatusCode(resp.status))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_response_headers(
  self,
) {
  let resp_id = self.current_incoming_response
  match self.kernel.http_incoming_responses.get(resp_id) {
    None => Err(stream_closed_error())
    Some(resp) => Ok(@p2.HttpTypesHeaders(resp.headers_id))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_response_consume(
  self,
) {
  let resp_id = self.current_incoming_response
  match self.kernel.http_incoming_responses.get(resp_id) {
    None => Err(stream_closed_error())
    Some(resp) => {
      let body_id = self.kernel.alloc_incoming_body({
        data: resp.body_data,
        offset: 0,
        stream_id: None,
      })
      self.current_incoming_body = body_id
      Ok(@p2.HttpTypesIncomingBody(body_id))
    }
  }
}

// ===== Future Trailers =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with future_trailers_subscribe(
  self,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.HttpTypesPollable(id))
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with future_trailers_get(
  _self,
) {
  Ok(Some(Ok(Ok(None))))
}

// ===== Outgoing Response =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_response_constructor(
  self,
  headers,
) {
  let id = self.kernel.alloc_outgoing_response({
    headers_id: headers.0,
    status: 200,
    body_id: None,
  })
  self.current_outgoing_response = id
  Ok(())
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_response_status_code(
  self,
) {
  let id = self.current_outgoing_response
  match self.kernel.http_outgoing_responses.get(id) {
    None => Err(stream_closed_error())
    Some(resp) => Ok(@p2.HttpTypesStatusCode(resp.status))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_response_headers(
  self,
) {
  let id = self.current_outgoing_response
  match self.kernel.http_outgoing_responses.get(id) {
    None => Err(stream_closed_error())
    Some(resp) => Ok(@p2.HttpTypesHeaders(resp.headers_id))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_response_body(
  self,
) {
  let resp_id = self.current_outgoing_response
  match self.kernel.http_outgoing_responses.get(resp_id) {
    None => Err(stream_closed_error())
    Some(resp) => {
      let body_id = self.kernel.alloc_outgoing_body({
        buffer: [],
        stream_id: None,
      })
      resp.body_id = Some(body_id)
      self.current_outgoing_body = body_id
      Ok(@p2.HttpTypesOutgoingBody(body_id))
    }
  }
}

// ===== Outgoing Body =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with outgoing_body_write(self) {
  let body_id = self.current_outgoing_body
  match self.kernel.http_outgoing_bodies.get(body_id) {
    None => Err(stream_closed_error())
    Some(body) => {
      let stream_id = self.kernel.alloc_stream(HttpBodyWrite(body_id))
      body.stream_id = Some(stream_id)
      Ok(@p2.HttpTypesOutputStream(stream_id))
    }
  }
}

// ===== Future Incoming Response =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with future_incoming_response_subscribe(
  self,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.HttpTypesPollable(id))
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with future_incoming_response_get(
  self,
) {
  let future_id = self.current_future
  match self.kernel.http_futures.get(future_id) {
    None => Ok(None)
    Some(f) =>
      match f.response_id {
        None => Ok(None)
        Some(resp_id) => {
          self.current_incoming_response = resp_id
          Ok(Some(Ok(Ok(@p2.HttpTypesIncomingResponse(resp_id)))))
        }
      }
  }
}

// ===== Incoming Request =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_method(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(string_to_method(req.method_))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_path_with_query(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(Some(req.path))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_scheme(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) =>
      match req.scheme {
        None => Ok(None)
        Some(s) => Ok(Some(string_to_scheme(s)))
      }
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_authority(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(req.authority)
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_headers(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) => Ok(@p2.HttpTypesHeaders(req.headers_id))
  }
}

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with incoming_request_consume(
  self,
) {
  let id = self.current_incoming_request
  match self.kernel.http_incoming_requests.get(id) {
    None => Err(stream_closed_error())
    Some(req) => {
      let body_id = self.kernel.alloc_incoming_body({
        data: req.body_data,
        offset: 0,
        stream_id: None,
      })
      self.current_incoming_body = body_id
      Ok(@p2.HttpTypesIncomingBody(body_id))
    }
  }
}

// ===== Error Code =====

///|
pub impl @p2.WasiHttpTypesAdapter for HttpAdapter with http_error_code(
  _self,
  _err,
) {
  Ok(None)
}

// ===== Outgoing Handler =====

///|
pub impl @p2.WasiHttpOutgoingHandlerAdapter for HttpAdapter with handle(
  self,
  req,
  _options,
) {
  let req_id = req.0
  match self.kernel.http_outgoing_requests.get(req_id) {
    None => Err(stream_closed_error())
    Some(out_req) => {
      // Collect body bytes
      let body_bytes : Bytes = match out_req.body_id {
        None => b""
        Some(body_id) =>
          match self.kernel.http_outgoing_bodies.get(body_id) {
            None => b""
            Some(body) => Bytes::from_iter(body.buffer.iter())
          }
      }
      // Collect headers
      let headers = fields_to_pairs(self.kernel, out_req.headers_id)
      // Call mock handler or return 404
      let (status, resp_headers, resp_body) = match
        self.kernel.http_mock_handler {
        None => (404, ([] : Array[(String, Bytes)]), b"")
        Some(handler) =>
          handler(out_req.method_, out_req.path, headers, body_bytes)
      }
      // Build response fields
      let resp_fields_id = pairs_to_fields(self.kernel, resp_headers)
      // Build incoming response
      let resp_id = self.kernel.alloc_incoming_response({
        status,
        headers_id: resp_fields_id,
        body_data: resp_body,
      })
      // Build future (immediately resolved)
      let future_id = self.kernel.alloc_future({ response_id: Some(resp_id) })
      self.current_future = future_id
      Ok(@p2.HttpOutgoingHandlerFutureIncomingResponse(future_id))
    }
  }
}

// ===== Incoming Handler =====

///|
pub impl @p2.WasiHttpIncomingHandlerAdapter for HttpAdapter with handle(
  self,
  _req,
  _outparam,
) {
  // Incoming handler is typically for server-side use.
  // In mock mode, we just return Ok since this is mainly for testing.
  let _ = self
  Ok(())
}

// ===== Helper functions =====

///|
fn string_to_method(s : String) -> @p2.HttpTypesMethod {
  match s {
    "GET" => @p2.HttpTypesMethod::Get
    "HEAD" => @p2.HttpTypesMethod::Head
    "POST" => @p2.HttpTypesMethod::Post
    "PUT" => @p2.HttpTypesMethod::Put
    "DELETE" => @p2.HttpTypesMethod::Delete
    "CONNECT" => @p2.HttpTypesMethod::Connect
    "OPTIONS" => @p2.HttpTypesMethod::Options
    "TRACE" => @p2.HttpTypesMethod::Trace
    "PATCH" => @p2.HttpTypesMethod::Patch
    _ => @p2.HttpTypesMethod::Other(s)
  }
}

///|
fn string_to_scheme(s : String) -> @p2.HttpTypesScheme {
  match s {
    "http" => @p2.HttpTypesScheme::Http
    "https" => @p2.HttpTypesScheme::Https
    _ => @p2.HttpTypesScheme::Other(s)
  }
}

///|
fn string_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}
