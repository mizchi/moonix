# Moonix workspace commands

target := "wasm-gc"
home := env_var_or_default("HOME", "/tmp")
prefix := env_var_or_default("MOONIX_PREFIX", home + "/.local")
bindir := prefix + "/bin"
moonix_bin := "hosts/wasmtime/target/release/moonix"

default: check test

check:
    moon check --target {{target}}

test:
    moon test --target {{target}}

xsh-check:
    cd ../xsh && moon check --target {{target}}

xsh-test:
    cd ../xsh && moon test --target {{target}}

workspace: check test xsh-check xsh-test

build:
    cargo build --release --manifest-path hosts/wasmtime/Cargo.toml --bin moonix

install: build
    mkdir -p {{bindir}}
    cp {{moonix_bin}} {{bindir}}/moonix
