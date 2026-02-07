use anyhow::{bail, Context, Result};
use std::process::ExitCode;
use wasmtime::component::{Component, Linker, ResourceTable};
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::p2::add_to_linker_sync;
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiCtxView, WasiView};

#[derive(Debug, Clone, PartialEq, Eq)]
struct RunOptions {
    component: String,
    invoke: String,
    passthrough: Vec<String>,
}

fn print_usage() {
    eprintln!("moonix - component runner");
    eprintln!();
    eprintln!("usage:");
    eprintln!("  moonix run <component.wasm> [--invoke <signature>] [-- <invoke-args...>]");
    eprintln!(
        "  moonix component run <component.wasm> [--invoke <signature>] [-- <invoke-args...>]"
    );
    eprintln!();
    eprintln!("examples:");
    eprintln!("  moonix run dist/test_import.component.wasm --invoke 'run()'");
    eprintln!("  moonix component run dist/test_import.component.wasm");
}

struct CliState {
    ctx: WasiCtx,
    table: ResourceTable,
}

impl WasiView for CliState {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView {
            ctx: &mut self.ctx,
            table: &mut self.table,
        }
    }
}

fn parse_run_args(args: &[String]) -> Result<RunOptions> {
    let mut invoke = "run()".to_string();
    let mut component: Option<String> = None;
    let mut passthrough: Vec<String> = Vec::new();
    let mut after_sep = false;
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        if after_sep {
            passthrough.push(arg.clone());
            i += 1;
            continue;
        }
        match arg.as_str() {
            "--" => {
                after_sep = true;
                i += 1;
            }
            "--invoke" => {
                i += 1;
                if i >= args.len() {
                    bail!("--invoke requires a signature");
                }
                invoke = args[i].clone();
                i += 1;
            }
            "-h" | "--help" => {
                print_usage();
                std::process::exit(0);
            }
            _ if arg.starts_with('-') => {
                bail!("unknown option: {arg}");
            }
            _ => {
                if component.is_none() {
                    component = Some(arg.clone());
                } else {
                    passthrough.push(arg.clone());
                }
                i += 1;
            }
        }
    }

    let component = component.context("missing component path")?;
    Ok(RunOptions {
        component,
        invoke,
        passthrough,
    })
}

fn parse_args(raw: &[String]) -> Result<Option<RunOptions>> {
    if raw.is_empty() {
        print_usage();
        return Ok(None);
    }

    match raw[0].as_str() {
        "-h" | "--help" => {
            print_usage();
            Ok(None)
        }
        "run" => parse_run_args(&raw[1..]).map(Some),
        "component" => {
            if raw.len() < 2 || raw[1] != "run" {
                bail!("expected: moonix component run ...");
            }
            parse_run_args(&raw[2..]).map(Some)
        }
        other => bail!("unknown command: {other}"),
    }
}

fn parse_invoke_name(signature: &str) -> Result<&str> {
    let s = signature.trim();
    if s.is_empty() {
        bail!("empty invoke signature");
    }
    if let Some(open) = s.find('(') {
        if !s.ends_with(')') {
            bail!("invalid invoke signature: {signature}");
        }
        let name = s[..open].trim();
        if name.is_empty() {
            bail!("missing function name in invoke signature");
        }
        let args = s[open + 1..s.len() - 1].trim();
        if !args.is_empty() {
            bail!("invoke args are not supported yet: {signature}");
        }
        return Ok(name);
    }
    if s.contains(')') {
        bail!("invalid invoke signature: {signature}");
    }
    Ok(s)
}

fn run_component_in_process(opts: &RunOptions) -> Result<ExitCode> {
    let invoke_name = parse_invoke_name(&opts.invoke)?;

    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    let component = Component::from_file(&engine, &opts.component)
        .with_context(|| "failed to load component")?;
    let mut linker = Linker::<CliState>::new(&engine);
    add_to_linker_sync(&mut linker)?;

    let mut wasi_builder = WasiCtxBuilder::new();
    wasi_builder
        .allow_blocking_current_thread(true)
        .inherit_stdio()
        .inherit_env();
    let mut guest_args = Vec::with_capacity(1 + opts.passthrough.len());
    guest_args.push(opts.component.clone());
    guest_args.extend(opts.passthrough.clone());
    wasi_builder.args(&guest_args);

    let state = CliState {
        ctx: wasi_builder.build(),
        table: ResourceTable::new(),
    };
    let mut store = Store::new(&engine, state);
    let instance = linker
        .instantiate(&mut store, &component)
        .with_context(|| "failed to instantiate component")?;

    if let Ok(func) = instance.get_typed_func::<(), (i32,)>(&mut store, invoke_name) {
        let (value,) = func.call(&mut store, ())?;
        println!("{value}");
        return Ok(ExitCode::SUCCESS);
    }
    if let Ok(func) = instance.get_typed_func::<(), ()>(&mut store, invoke_name) {
        func.call(&mut store, ())?;
        return Ok(ExitCode::SUCCESS);
    }
    if instance.get_func(&mut store, invoke_name).is_none() {
        let mut exports = component
            .component_type()
            .exports(&engine)
            .map(|(name, _)| name.to_string())
            .collect::<Vec<_>>();
        exports.sort();
        let exports_str = if exports.is_empty() {
            "<none>".to_string()
        } else {
            exports.join(", ")
        };
        bail!(
            "invoke export `{invoke_name}` was not found (or is not a function). available root exports: {exports_str}"
        );
    }
    bail!(
        "unsupported invoke signature for export `{invoke_name}`; currently supports () -> s32 or () -> ()"
    );
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse_args(&args) {
        Ok(None) => ExitCode::SUCCESS,
        Ok(Some(opts)) => match run_component_in_process(&opts) {
            Ok(code) => code,
            Err(err) => {
                eprintln!("moonix: {err:#}");
                ExitCode::FAILURE
            }
        },
        Err(err) => {
            eprintln!("moonix: {err:#}");
            print_usage();
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_args, parse_invoke_name, RunOptions};

    fn s(xs: &[&str]) -> Vec<String> {
        xs.iter().map(|x| (*x).to_string()).collect()
    }

    #[test]
    fn parse_run_component_then_invoke() {
        let args = s(&["run", "a.component.wasm", "--invoke", "run()"]);
        let got = parse_args(&args).expect("parse").expect("command");
        assert_eq!(
            got,
            RunOptions {
                component: "a.component.wasm".to_string(),
                invoke: "run()".to_string(),
                passthrough: vec![],
            }
        );
    }

    #[test]
    fn parse_run_invoke_then_component() {
        let args = s(&["run", "--invoke", "f()", "a.component.wasm"]);
        let got = parse_args(&args).expect("parse").expect("command");
        assert_eq!(got.component, "a.component.wasm");
        assert_eq!(got.invoke, "f()");
    }

    #[test]
    fn parse_component_run_variant() {
        let args = s(&["component", "run", "a.component.wasm"]);
        let got = parse_args(&args).expect("parse").expect("command");
        assert_eq!(got.component, "a.component.wasm");
        assert_eq!(got.invoke, "run()");
    }

    #[test]
    fn parse_with_passthrough_after_sep() {
        let args = s(&["run", "a.component.wasm", "--", "1", "2"]);
        let got = parse_args(&args).expect("parse").expect("command");
        assert_eq!(got.passthrough, vec!["1".to_string(), "2".to_string()]);
    }

    #[test]
    fn parse_invoke_name_accepts_empty_args() {
        assert_eq!(parse_invoke_name("run()").expect("invoke"), "run");
        assert_eq!(parse_invoke_name("run").expect("invoke"), "run");
        assert_eq!(parse_invoke_name("  run (   ) ").expect("invoke"), "run");
    }

    #[test]
    fn parse_invoke_name_rejects_args() {
        assert!(parse_invoke_name("run(1)").is_err());
        assert!(parse_invoke_name("run(a, b)").is_err());
    }
}
