use rand_core::{CryptoRng, Error, RngCore};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wasmtime_wasi::clocks::{HostMonotonicClock, HostWallClock};

/// Deterministic clock for virtualized environments.
pub struct VirtualClock {
    wall_ns: u64,
    mono_ns: u64,
    step_ns: u64,
}

impl VirtualClock {
    pub fn new(wall_ns: u64, mono_ns: u64, step_ns: u64) -> Self {
        Self {
            wall_ns,
            mono_ns,
            step_ns: step_ns.max(1),
        }
    }

    pub fn wall_time_ns(&mut self) -> u64 {
        let t = self.wall_ns;
        self.wall_ns = self.wall_ns.saturating_add(self.step_ns);
        t
    }

    pub fn monotonic_time_ns(&mut self) -> u64 {
        let t = self.mono_ns;
        self.mono_ns = self.mono_ns.saturating_add(self.step_ns);
        t
    }

    pub fn resolution_ns(&self) -> u64 {
        self.step_ns
    }
}

/// Wrapper for WASI wall clock.
#[derive(Clone)]
pub struct VirtualWallClock {
    clock: Arc<Mutex<VirtualClock>>,
}

impl VirtualWallClock {
    pub fn new(clock: Arc<Mutex<VirtualClock>>) -> Self {
        Self { clock }
    }
}

impl HostWallClock for VirtualWallClock {
    fn resolution(&self) -> Duration {
        let clock = self.clock.lock().expect("virtual clock");
        Duration::from_nanos(clock.resolution_ns())
    }

    fn now(&self) -> Duration {
        let mut clock = self.clock.lock().expect("virtual clock");
        Duration::from_nanos(clock.wall_time_ns())
    }
}

/// Wrapper for WASI monotonic clock.
#[derive(Clone)]
pub struct VirtualMonotonicClock {
    clock: Arc<Mutex<VirtualClock>>,
}

impl VirtualMonotonicClock {
    pub fn new(clock: Arc<Mutex<VirtualClock>>) -> Self {
        Self { clock }
    }
}

impl HostMonotonicClock for VirtualMonotonicClock {
    fn resolution(&self) -> u64 {
        let clock = self.clock.lock().expect("virtual clock");
        clock.resolution_ns()
    }

    fn now(&self) -> u64 {
        let mut clock = self.clock.lock().expect("virtual clock");
        clock.monotonic_time_ns()
    }
}

/// Deterministic RNG for virtualized environments.
#[derive(Clone)]
pub struct VirtualRng {
    state: u64,
}

impl VirtualRng {
    pub fn new(seed: u64) -> Self {
        let seed = if seed == 0 { 0x9e3779b97f4a7c15 } else { seed };
        Self { state: seed }
    }

    fn next(&mut self) -> u64 {
        // xorshift64*
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(0x2545f4914f6c_dd1d)
    }
}

impl RngCore for VirtualRng {
    fn next_u32(&mut self) -> u32 {
        self.next() as u32
    }

    fn next_u64(&mut self) -> u64 {
        self.next()
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        let mut i = 0;
        while i < dest.len() {
            let n = self.next_u64();
            for b in n.to_le_bytes() {
                if i >= dest.len() {
                    break;
                }
                dest[i] = b;
                i += 1;
            }
        }
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), Error> {
        self.fill_bytes(dest);
        Ok(())
    }
}

impl CryptoRng for VirtualRng {}
