///|
pub struct NetworkAdapter {
  _unused : Int
}

///|
pub fn NetworkAdapter::new() -> NetworkAdapter {
  { _unused: 0 }
}

///|
fn deny_network() -> @p3.WasiError {
  @p3.WasiError::FromIpnamelookuperrorcode(
    @p3.IpNameLookupErrorCode::AccessDenied,
  )
}

///|
pub impl @p3.WasiIpNameLookupAdapter for NetworkAdapter with resolve_addresses(
  _self,
  _name,
) {
  Err(deny_network())
}
