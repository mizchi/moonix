///|
pub struct SocketsAdapter {
  _unused : Int
}

///|
pub fn SocketsAdapter::new() -> SocketsAdapter {
  { _unused: 0 }
}

///|
fn deny_socket() -> @p2.WasiError {
  @p2.WasiError::CapabilityDenied("sockets not available in memory adapter")
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_start_bind(
  _self,
  _network,
  _addr,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_finish_bind(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_start_connect(
  _self,
  _network,
  _addr,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_finish_connect(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_start_listen(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_finish_listen(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_accept(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_local_address(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_remote_address(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_is_listening(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_address_family(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_listen_backlog_size(
  _self,
  _size,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_keep_alive_enabled(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_keep_alive_enabled(
  _self,
  _enabled,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_keep_alive_idle_time(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_keep_alive_idle_time(
  _self,
  _duration,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_keep_alive_interval(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_keep_alive_interval(
  _self,
  _duration,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_keep_alive_count(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_keep_alive_count(
  _self,
  _count,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_hop_limit(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_hop_limit(
  _self,
  _limit,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_receive_buffer_size(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_receive_buffer_size(
  _self,
  _size,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_send_buffer_size(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_set_send_buffer_size(
  _self,
  _size,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_subscribe(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpAdapter for SocketsAdapter with tcp_socket_shutdown(
  _self,
  _type,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsTcpCreateSocketAdapter for SocketsAdapter with create_tcp_socket(
  _self,
  _family,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_start_bind(
  _self,
  _network,
  _addr,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_finish_bind(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_local_address(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_remote_address(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_address_family(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_unicast_hop_limit(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_set_unicast_hop_limit(
  _self,
  _limit,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_receive_buffer_size(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_set_receive_buffer_size(
  _self,
  _size,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_send_buffer_size(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_set_send_buffer_size(
  _self,
  _size,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with udp_socket_subscribe(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with incoming_datagram_stream_receive(
  _self,
  _max,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with incoming_datagram_stream_subscribe(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with outgoing_datagram_stream_check_send(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with outgoing_datagram_stream_send(
  _self,
  _datagrams,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpAdapter for SocketsAdapter with outgoing_datagram_stream_subscribe(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsUdpCreateSocketAdapter for SocketsAdapter with create_udp_socket(
  _self,
  _family,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsNetworkAdapter for SocketsAdapter with network_error_code(
  _self,
  _err,
) {
  Ok(None)
}

///|
pub impl @p2.WasiSocketsIpNameLookupAdapter for SocketsAdapter with resolve_address_stream_resolve_next_address(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsIpNameLookupAdapter for SocketsAdapter with resolve_address_stream_subscribe(
  _self,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsIpNameLookupAdapter for SocketsAdapter with resolve_addresses(
  _self,
  _network,
  _name,
) {
  Err(deny_socket())
}

///|
pub impl @p2.WasiSocketsInstanceNetworkAdapter for SocketsAdapter with instance_network(
  _self,
) {
  Err(deny_socket())
}
