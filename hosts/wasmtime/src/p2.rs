use crate::fs_bridge::FsBridge;
use crate::memfs::MemFs;
use crate::virtual_kernel::{VirtualClock, VirtualMonotonicClock, VirtualRng, VirtualWallClock};
use anyhow::Result;
use std::sync::{Arc, Mutex};
use wasmtime::component::{Linker, ResourceTable};
use wasmtime::Engine;
use wasmtime_wasi::p2::add_to_linker_sync;
use wasmtime_wasi::{DirPerms, FilePerms, WasiCtx, WasiCtxBuilder, WasiCtxView, WasiView};

/// State for WASIp2 host.
pub struct P2State {
    table: ResourceTable,
    ctx: WasiCtx,
    pub kernel: Arc<Mutex<VirtualClock>>,
    pub fs_bridge: Option<FsBridge>,
}

impl WasiView for P2State {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView {
            ctx: &mut self.ctx,
            table: &mut self.table,
        }
    }
}

/// Build a WASIp2 state with deterministic clocks/random and no OS side effects.
/// If `initial_fs` is provided, materialize it as a preopened directory at "/".
pub fn build_state(seed: u64, initial_fs: Option<MemFs>) -> Result<P2State> {
    let kernel = Arc::new(Mutex::new(VirtualClock::new(1_000, 5_000, 10)));
    let wall_clock = VirtualWallClock::new(kernel.clone());
    let mono_clock = VirtualMonotonicClock::new(kernel.clone());

    let secure_rng = VirtualRng::new(seed ^ 0x9e3779b97f4a7c15);
    let insecure_rng = VirtualRng::new(seed);

    let mut builder = WasiCtxBuilder::new();
    builder.wall_clock(wall_clock);
    builder.monotonic_clock(mono_clock);
    builder.secure_random(Box::new(secure_rng));
    builder.insecure_random(Box::new(insecure_rng));
    builder.insecure_random_seed(seed as u128);

    // Deny all socket addresses explicitly.
    builder.allow_ip_name_lookup(false);
    builder.allow_tcp(false);
    builder.allow_udp(false);
    builder.socket_addr_check(|_, _| Box::pin(async { false }));

    let fs_bridge = if let Some(memfs) = initial_fs {
        let mut bridge = FsBridge::new(memfs);
        let path = bridge.materialize().map_err(|e| anyhow::anyhow!("{e}"))?;
        builder.preopened_dir(&path, "/", DirPerms::all(), FilePerms::all())?;
        Some(bridge)
    } else {
        None
    };

    let ctx = builder.build();

    Ok(P2State {
        table: ResourceTable::new(),
        ctx,
        kernel,
        fs_bridge,
    })
}

impl P2State {
    /// Snapshot the current tempdir contents back into the MemFs.
    pub fn snapshot_fs(&mut self) -> Result<()> {
        if let Some(bridge) = &mut self.fs_bridge {
            bridge.snapshot().map_err(|e| anyhow::anyhow!("{e}"))
        } else {
            Ok(())
        }
    }

    /// Take the FsBridge out of this state, consuming it.
    pub fn take_fs(&mut self) -> Option<FsBridge> {
        self.fs_bridge.take()
    }
}

/// Build a WASIp2 linker.
pub fn build_linker(engine: &Engine) -> Result<Linker<P2State>> {
    let mut linker = Linker::new(engine);
    add_to_linker_sync(&mut linker)?;
    Ok(linker)
}
