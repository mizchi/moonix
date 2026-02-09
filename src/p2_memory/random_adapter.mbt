///|
pub struct RandomAdapter {
  kernel : Kernel
}

///|
pub fn RandomAdapter::new(kernel : Kernel) -> RandomAdapter {
  { kernel, }
}

///|
pub impl @p2.WasiRandomRandomAdapter for RandomAdapter with get_random_bytes(
  self,
  len,
) {
  Ok(self.kernel.next_random_bytes(len.to_int()))
}

///|
pub impl @p2.WasiRandomRandomAdapter for RandomAdapter with get_random_u64(self) {
  Ok(self.kernel.next_random_u64())
}

///|
pub impl @p2.WasiRandomInsecureAdapter for RandomAdapter with get_insecure_random_bytes(
  self,
  len,
) {
  Ok(self.kernel.next_random_bytes(len.to_int()))
}

///|
pub impl @p2.WasiRandomInsecureAdapter for RandomAdapter with get_insecure_random_u64(
  self,
) {
  Ok(self.kernel.next_random_u64())
}

///|
pub impl @p2.WasiRandomInsecureSeedAdapter for RandomAdapter with insecure_seed(
  self,
) {
  Ok(self.kernel.next_random_bytes(16))
}
