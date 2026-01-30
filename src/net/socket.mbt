///| Virtual socket implementation

/// Virtual socket
pub struct VSocket {
  id : Int
  mut state : SocketState
  mut local_addr : NetAddr?
  mut remote_addr : NetAddr?
  mut recv_buffer : Array[Byte]
  send_buffer : Array[Byte]
}

/// Global socket ID counter
let next_socket_id : Ref[Int] = { val: 1 }

pub fn VSocket::new() -> VSocket {
  let id = next_socket_id.val
  next_socket_id.val += 1
  {
    id,
    state: SocketState::Created,
    local_addr: None,
    remote_addr: None,
    recv_buffer: [],
    send_buffer: [],
  }
}

pub fn VSocket::get_id(self : VSocket) -> Int {
  self.id
}

pub fn VSocket::get_state(self : VSocket) -> SocketState {
  self.state
}

pub fn VSocket::get_local_addr(self : VSocket) -> NetAddr? {
  self.local_addr
}

/// Bind socket to address
pub fn VSocket::bind(self : VSocket, addr : NetAddr) -> Unit raise NetError {
  match self.state {
    Created => {
      self.local_addr = Some(addr)
      self.state = Bound
    }
    _ => raise NetError::InvalidState("Cannot bind in current state")
  }
}

/// Start listening
pub fn VSocket::listen(self : VSocket) -> Unit raise NetError {
  match self.state {
    Bound => self.state = Listening
    _ => raise NetError::InvalidState("Socket must be bound before listening")
  }
}

/// Close socket
pub fn VSocket::close(self : VSocket) -> Unit {
  self.state = Closed
  self.recv_buffer.clear()
  self.send_buffer.clear()
}

/// Write data to socket
pub fn VSocket::write(self : VSocket, data : Bytes) -> Int raise NetError {
  match self.state {
    Connected => {
      for b in data {
        self.send_buffer.push(b)
      }
      data.length()
    }
    Closed => raise NetError::Closed
    _ => raise NetError::NotConnected
  }
}

/// Read data from socket
pub fn VSocket::read(self : VSocket, max_len : Int) -> Bytes raise NetError {
  match self.state {
    Connected => {
      let len = if self.recv_buffer.length() < max_len {
        self.recv_buffer.length()
      } else {
        max_len
      }
      let result = Bytes::makei(len, fn(i) { self.recv_buffer[i] })
      // Remove read bytes from buffer
      let remaining : Array[Byte] = []
      for i = len; i < self.recv_buffer.length(); i = i + 1 {
        remaining.push(self.recv_buffer[i])
      }
      self.recv_buffer = remaining
      result
    }
    Closed => raise NetError::Closed
    _ => raise NetError::NotConnected
  }
}

/// Check if there's data available to read
pub fn VSocket::has_data(self : VSocket) -> Bool {
  self.recv_buffer.length() > 0
}

/// Internal: push data to receive buffer (used by VirtualNetwork)
pub fn VSocket::push_recv_data(self : VSocket, data : Bytes) -> Unit {
  for b in data {
    self.recv_buffer.push(b)
  }
}

/// Internal: pop data from send buffer (used by VirtualNetwork)
pub fn VSocket::pop_send_data(self : VSocket) -> Bytes {
  let result = Bytes::makei(self.send_buffer.length(), fn(i) { self.send_buffer[i] })
  self.send_buffer.clear()
  result
}

/// Internal: set connected state
pub fn VSocket::set_connected(self : VSocket, remote : NetAddr) -> Unit {
  self.state = Connected
  self.remote_addr = Some(remote)
}
