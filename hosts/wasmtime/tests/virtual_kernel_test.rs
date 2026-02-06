use wasmtime_host_experiments::memfs::MemFs;
use wasmtime_host_experiments::p2;
use wasmtime_host_experiments::p3;
use wasmtime_host_experiments::virtual_kernel::{VirtualClock, VirtualRng};
use rand_core::RngCore;

#[test]
fn virtual_clock_is_deterministic() {
    let mut clock = VirtualClock::new(1_000, 5_000, 10);
    assert_eq!(clock.wall_time_ns(), 1_000);
    assert_eq!(clock.wall_time_ns(), 1_010);
    assert_eq!(clock.monotonic_time_ns(), 5_000);
    assert_eq!(clock.monotonic_time_ns(), 5_010);
}

#[test]
fn virtual_rng_is_deterministic() {
    let mut rng1 = VirtualRng::new(42);
    let mut rng2 = VirtualRng::new(42);
    assert_eq!(rng1.next_u64(), rng2.next_u64());
    assert_eq!(rng1.next_u64(), rng2.next_u64());
}

#[test]
fn build_p2_linker() {
    let engine = wasmtime::Engine::default();
    let _linker = p2::build_linker(&engine).expect("p2 linker");
}

#[test]
fn build_p3_linker() {
    let engine = p3::build_engine().expect("p3 engine");
    let _linker = p3::build_linker(&engine).expect("p3 linker");
}

#[test]
fn build_p2_state_without_fs() {
    let _state = p2::build_state(42, None).expect("p2 state without fs");
}

#[test]
fn build_p3_state_without_fs() {
    let _state = p3::build_state(42, None).expect("p3 state without fs");
}

#[test]
fn p2_state_with_filesystem() {
    let mut fs = MemFs::new();
    fs.mkdir("/src").unwrap();
    fs.write_string("/src/main.rs", "fn main() {}").unwrap();

    let mut state = p2::build_state(42, Some(fs)).expect("p2 state with fs");
    assert!(state.fs_bridge.is_some());

    // Snapshot back
    state.snapshot_fs().expect("snapshot");

    // Take the bridge and verify contents
    let bridge = state.take_fs().expect("take_fs");
    let memfs = bridge.into_memfs();
    assert!(memfs.is_dir("/src"));
    assert_eq!(memfs.read_string("/src/main.rs").unwrap(), "fn main() {}");
}

#[test]
fn p3_state_with_filesystem() {
    let mut fs = MemFs::new();
    fs.mkdir("/data").unwrap();
    fs.write_string("/data/config.json", r#"{"key":"value"}"#).unwrap();

    let mut state = p3::build_state(42, Some(fs)).expect("p3 state with fs");
    assert!(state.fs_bridge.is_some());

    // Snapshot back
    state.snapshot_fs().expect("snapshot");

    // Take the bridge and verify contents
    let bridge = state.take_fs().expect("take_fs");
    let memfs = bridge.into_memfs();
    assert!(memfs.is_dir("/data"));
    assert_eq!(
        memfs.read_string("/data/config.json").unwrap(),
        r#"{"key":"value"}"#
    );
}
