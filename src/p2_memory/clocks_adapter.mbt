///|
pub struct ClocksAdapter {
  kernel : Kernel
}

///|
pub fn ClocksAdapter::new(kernel : Kernel) -> ClocksAdapter {
  { kernel, }
}

///|
pub impl @p2.WasiClocksWallClockAdapter for ClocksAdapter with fn now(self) {
  Ok(@p2.ClocksWallClockDatetime::{
    seconds: self.kernel.wall_seconds,
    nanoseconds: self.kernel.wall_nanoseconds,
  })
}

///|
pub impl @p2.WasiClocksWallClockAdapter for ClocksAdapter with fn resolution(
  _self,
) {
  Ok(@p2.ClocksWallClockDatetime::{ seconds: 0UL, nanoseconds: 1 })
}

///|
pub impl @p2.WasiClocksMonotonicClockAdapter for ClocksAdapter with fn now(self) {
  Ok(@p2.ClocksMonotonicClockInstant(self.kernel.monotonic_ns))
}

///|
pub impl @p2.WasiClocksMonotonicClockAdapter for ClocksAdapter with fn resolution(
  _self,
) {
  Ok(@p2.ClocksMonotonicClockDuration(1UL))
}

///|
pub impl @p2.WasiClocksMonotonicClockAdapter for ClocksAdapter with fn subscribe_instant(
  self,
  _when,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.ClocksMonotonicClockPollable(id))
}

///|
pub impl @p2.WasiClocksMonotonicClockAdapter for ClocksAdapter with fn subscribe_duration(
  self,
  _duration,
) {
  let id = self.kernel.alloc_pollable()
  Ok(@p2.ClocksMonotonicClockPollable(id))
}

///|
pub impl @p2.WasiClocksTimezoneAdapter for ClocksAdapter with fn display(
  _self,
  _datetime,
) {
  Ok(@p2.ClocksTimezoneTimezoneDisplay::{
    utc_offset: 0,
    name: "UTC",
    in_daylight_saving_time: false,
  })
}

///|
pub impl @p2.WasiClocksTimezoneAdapter for ClocksAdapter with fn utc_offset(
  _self,
  _datetime,
) {
  Ok(0)
}
