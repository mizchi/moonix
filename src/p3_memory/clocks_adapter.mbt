///|
pub struct ClocksAdapter {
  kernel : Kernel
}

///|
pub fn ClocksAdapter::new(kernel : Kernel) -> ClocksAdapter {
  { kernel, }
}

///|
pub impl @p3.WasiClocksSystemClockAdapter for ClocksAdapter with now(self) {
  Ok(@p3.ClocksSystemClockInstant::{
    seconds: self.kernel.wall_seconds.reinterpret_as_int64(),
    nanoseconds: self.kernel.wall_nanoseconds,
  })
}

///|
pub impl @p3.WasiClocksSystemClockAdapter for ClocksAdapter with get_resolution(
  _self,
) {
  Ok(@p3.ClocksTypesDuration(1UL))
}

///|
pub impl @p3.WasiClocksMonotonicClockAdapter for ClocksAdapter with now(self) {
  Ok(@p3.ClocksMonotonicClockMark(self.kernel.monotonic_ns))
}

///|
pub impl @p3.WasiClocksMonotonicClockAdapter for ClocksAdapter with get_resolution(
  _self,
) {
  Ok(@p3.ClocksTypesDuration(1UL))
}

///|
pub impl @p3.WasiClocksMonotonicClockAdapter for ClocksAdapter with wait_until(
  _self,
  _when,
) {
  Ok(())
}

///|
pub impl @p3.WasiClocksMonotonicClockAdapter for ClocksAdapter with wait_for(
  _self,
  _duration,
) {
  Ok(())
}

///|
pub impl @p3.WasiClocksTimezoneAdapter for ClocksAdapter with iana_id(_self) {
  Ok(Some("UTC"))
}

///|
pub impl @p3.WasiClocksTimezoneAdapter for ClocksAdapter with utc_offset(
  _self,
  _instant,
) {
  Ok(Some(0L))
}

///|
pub impl @p3.WasiClocksTimezoneAdapter for ClocksAdapter with to_debug_string(
  _self,
) {
  Ok("UTC+0")
}
