///| Virtual network - manages connections between virtual sockets

///|
/// Connection between two sockets
struct Connection {
  client : VSocket
  server : VSocket
}

///|
/// Virtual network manager
pub struct VirtualNetwork {
  /// Listening sockets: port -> socket
  listeners : Map[Int, VSocket]
  /// Active connections
  mut connections : Array[Connection]
  /// Pending connections waiting to be accepted
  pending : Map[Int, Array[VSocket]]
}

///|
pub fn VirtualNetwork::new() -> VirtualNetwork {
  { listeners: {}, connections: [], pending: {} }
}

///|
/// Register a listening socket
pub fn VirtualNetwork::register_listener(
  self : VirtualNetwork,
  socket : VSocket,
) -> Unit raise NetError {
  match socket.get_local_addr() {
    Some(addr) => {
      if self.listeners.contains(addr.port) {
        raise NetError::AddressInUse("Port \{addr.port} already in use")
      }
      self.listeners[addr.port] = socket
      self.pending[addr.port] = []
    }
    None => raise NetError::NotBound
  }
}

///|
/// Connect to a listening socket
pub fn VirtualNetwork::connect(
  self : VirtualNetwork,
  client : VSocket,
  addr : NetAddr,
) -> Unit raise NetError {
  match self.listeners.get(addr.port) {
    Some(_listener) => {
      // Create connection pair
      client.set_connected(addr)

      // Add to pending connections for accept()
      match self.pending.get(addr.port) {
        Some(pending_list) => pending_list.push(client)
        None => self.pending[addr.port] = [client]
      }
    }
    None =>
      raise NetError::ConnectionRefused("No listener on port \{addr.port}")
  }
}

///|
/// Accept a pending connection (returns client socket)
pub fn VirtualNetwork::accept(
  self : VirtualNetwork,
  server : VSocket,
) -> VSocket? {
  match server.get_local_addr() {
    Some(addr) =>
      match self.pending.get(addr.port) {
        Some(pending_list) =>
          if pending_list.length() > 0 {
            let client = pending_list.remove(0)
            // Create server-side socket for this connection
            let conn_socket = VSocket::new()
            conn_socket.set_connected(NetAddr::new("client", client.get_id()))

            // Register connection
            self.connections.push({ client, server: conn_socket })
            Some(conn_socket)
          } else {
            None
          }
        None => None
      }
    None => None
  }
}

///|
/// Transfer data between connected sockets
pub fn VirtualNetwork::transfer(self : VirtualNetwork) -> Unit {
  for conn in self.connections {
    // Client -> Server
    let client_data = conn.client.pop_send_data()
    if client_data.length() > 0 {
      conn.server.push_recv_data(client_data)
    }

    // Server -> Client
    let server_data = conn.server.pop_send_data()
    if server_data.length() > 0 {
      conn.client.push_recv_data(server_data)
    }
  }
}

///|
/// Check if there are pending connections
pub fn VirtualNetwork::has_pending(self : VirtualNetwork, port : Int) -> Bool {
  match self.pending.get(port) {
    Some(pending_list) => pending_list.length() > 0
    None => false
  }
}

///|
/// Remove closed connections
pub fn VirtualNetwork::cleanup(self : VirtualNetwork) -> Unit {
  let active : Array[Connection] = []
  for conn in self.connections {
    match (conn.client.get_state(), conn.server.get_state()) {
      (Closed, _) | (_, Closed) => ()
      _ => active.push(conn)
    }
  }
  self.connections = active
}
