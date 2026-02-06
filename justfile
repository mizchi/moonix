# Moonix workspace commands

target := "wasm-gc"

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
