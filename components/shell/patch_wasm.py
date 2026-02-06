#!/usr/bin/env python3
"""
Replace __moonbit_sys_unstable::is_windows import with a dummy WASI import
that has the same type signature.

Strategy: Replace the import module/name with an existing WASI import that
has the same type (type 49 = () -> i32). We use wasi:cli/stderr@0.2.9
get-stderr as the replacement since it has the same signature.

This approach keeps the import count the same, so no function index shifting
is needed. The duplicate import (two get-stderr imports) is valid wasm and
moon-component handles it fine.

Uses wasm-tools print/parse for round-tripping.
"""
import subprocess
import sys
import re
import tempfile
import os

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.wasm> <output.wasm>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    # Step 1: Convert to WAT
    result = subprocess.run(
        ["wasm-tools", "print", input_path],
        capture_output=True
    )
    if result.returncode != 0:
        print(f"Error: {result.stderr.decode()}", file=sys.stderr)
        sys.exit(1)

    wat = result.stdout.decode('utf-8', errors='replace')

    # Step 2: Find the __moonbit_sys_unstable import
    # Format: (import "__moonbit_sys_unstable" "is_windows" (func (;13;) (type 49)))
    pattern = r'\(import "__moonbit_sys_unstable" "is_windows" (\(func \(;\d+;\) \(type \d+\)\))\)'
    match = re.search(pattern, wat)

    if not match:
        print("No __moonbit_sys_unstable import found, copying input to output")
        subprocess.run(["cp", input_path, output_path])
        return

    func_part = match.group(1)
    print(f"Found: {match.group(0)}")

    # Step 3: Replace the import module/name but keep the func part identical
    # This preserves the function index so no other references need updating
    replacement = f'(import "wasi:cli/stderr@0.2.9" "get-stderr" {func_part})'
    wat_patched = wat[:match.start()] + replacement + wat[match.end():]

    print(f"Replaced with: {replacement}")

    # Step 4: Write temporary WAT and convert back to wasm
    with tempfile.NamedTemporaryFile(suffix='.wat', mode='w', delete=False, encoding='utf-8') as f:
        f.write(wat_patched)
        tmp_wat = f.name

    try:
        result = subprocess.run(
            ["wasm-tools", "parse", tmp_wat, "-o", output_path],
            capture_output=True
        )
        if result.returncode != 0:
            err = result.stderr.decode('utf-8', errors='replace')
            print(f"Error parsing patched WAT: {err}", file=sys.stderr)
            # Save the problematic WAT for debugging
            debug_path = output_path + '.debug.wat'
            subprocess.run(["cp", tmp_wat, debug_path])
            print(f"Debug WAT saved to: {debug_path}", file=sys.stderr)
            sys.exit(1)
        print(f"Successfully patched: {output_path}")
    finally:
        os.unlink(tmp_wat)

if __name__ == "__main__":
    main()
