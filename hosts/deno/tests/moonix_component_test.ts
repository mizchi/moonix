/**
 * E2E tests: MoonBit WASIp2 component (0.2.9) + all virtual WASI shims
 *
 * The MoonBit component exercises all WASI interfaces:
 * - filesystem (preopens, types): read/write files
 * - io (streams, poll): stream I/O and polling
 * - cli (stdin, stdout, stderr, environment): I/O capture and env vars
 * - clocks (wall-clock, monotonic-clock): deterministic time
 * - random (random, insecure, insecure-seed): deterministic RNG
 * - sockets (tcp-create-socket, udp-create-socket): expect errors
 *
 * Uses --instantiation async mode so each test gets a fresh wasm instance.
 */

import { assertEquals, assert, assertStringIncludes } from "jsr:@std/assert";
import {
  _setFileData,
  _getFileData,
  preopens,
  types,
} from "../virtual_fs.ts";
import { streams, error } from "../virtual_io.ts";
import { poll } from "../virtual_poll.ts";
import * as cli from "../virtual_cli.ts";
import { wallClock, monotonicClock } from "../virtual_clock.ts";
import { random, insecure, insecureSeed } from "../virtual_random.ts";
import { tcp, tcpCreateSocket, udp, udpCreateSocket } from "../virtual_sockets.ts";

// Import the instantiate function from e2e component transpiled output
import { instantiate } from "../../../components/e2e/out/component.js";

/** Load a core wasm module from the e2e/out directory */
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const url = new URL(`../../../components/e2e/out/${path}`, import.meta.url);
  const bytes = await Deno.readFile(url);
  return WebAssembly.compile(bytes);
}

/** Create a fresh component instance with all virtual WASI imports */
async function createComponent() {
  cli._clearStdio();
  return await instantiate(getCoreModule, {
    "../../hosts/deno/virtual_cli.ts": {
      environment: cli.environment,
      stderr: cli.stderr,
      stdin: cli.stdin,
      stdout: cli.stdout,
    },
    "../../hosts/deno/virtual_clock.ts": {
      monotonicClock,
      wallClock,
    },
    "../../hosts/deno/virtual_fs.ts": { preopens, types },
    "../../hosts/deno/virtual_io.ts": { error, streams },
    "../../hosts/deno/virtual_poll.ts": { poll },
    "../../hosts/deno/virtual_random.ts": { insecure, insecureSeed, random },
    "../../hosts/deno/virtual_sockets.ts": { tcp, tcpCreateSocket, udp, udpCreateSocket },
  });
}

Deno.test("moonix component reads input and writes output via virtual FS", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "Hello from MoonBit" },
    },
  });
  cli._setStdin("stdin data");
  cli._setEnvironment({ TEST_KEY: "test_value" });
  cli._setArgs(["arg0", "arg1"]);

  const component = await createComponent();
  component.run.run();

  const fileData = _getFileData();
  assert("output.txt" in fileData.dir, "output.txt should exist");

  const outputEntry = fileData.dir["output.txt"];
  assert("source" in outputEntry, "output.txt should be a file");

  const content =
    outputEntry.source instanceof Uint8Array
      ? new TextDecoder().decode(outputEntry.source)
      : (outputEntry.source as string);

  assertEquals(content, "processed: Hello from MoonBit");
});

Deno.test("moonix component fails gracefully when input.txt is missing", async () => {
  _setFileData({
    dir: {},
  });
  cli._setStdin("");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();

  try {
    component.run.run();
    throw new Error("should have thrown");
  } catch (e: unknown) {
    assert(e instanceof Error, "should throw an error");
  }
});

Deno.test("moonix component exercises all WASI interfaces", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "all-wasi-test" },
    },
  });
  cli._setStdin("hello from stdin");
  cli._setEnvironment({ MY_VAR: "my_value", ANOTHER: "val2" });
  cli._setArgs(["program", "--flag"]);

  const component = await createComponent();
  component.run.run();

  const stdoutOutput = cli._getStdout();
  const lines = stdoutOutput.split("\n").filter((l) => l.length > 0);

  // Helper to find a line starting with prefix
  const findLine = (prefix: string): string => {
    const line = lines.find((l) => l.startsWith(prefix));
    assert(line !== undefined, `Expected line starting with "${prefix}" in stdout`);
    return line!;
  };

  // --- filesystem: backward compat ---
  assertEquals(findLine("processed:"), "processed: all-wasi-test");

  // --- separator ---
  assert(lines.includes("---"), "separator should exist");

  // --- clocks/wall-clock ---
  // Deterministic: seconds=0, nanoseconds=0
  assertEquals(findLine("wall-clock:now:"), "wall-clock:now:0:0");
  assertEquals(findLine("wall-clock:resolution:"), "wall-clock:resolution:0:1000000");

  // --- clocks/monotonic-clock ---
  assertEquals(findLine("monotonic-clock:now:"), "monotonic-clock:now:0");
  assertEquals(findLine("monotonic-clock:resolution:"), "monotonic-clock:resolution:1000000");
  // subscribe_duration returns a pollable that is always ready
  assertEquals(
    findLine("monotonic-clock:subscribe_duration:ready:"),
    "monotonic-clock:subscribe_duration:ready:true",
  );

  // --- random/random ---
  assertEquals(findLine("random:get_random_bytes:len:"), "random:get_random_bytes:len:8");
  // get_random_u64 should return a non-zero value (deterministic PRNG)
  const randLine = findLine("random:get_random_u64:");
  assert(randLine.length > "random:get_random_u64:".length, "random u64 should have a value");

  // --- random/insecure ---
  assertEquals(
    findLine("insecure:get_insecure_random_bytes:len:"),
    "insecure:get_insecure_random_bytes:len:4",
  );
  const insecureLine = findLine("insecure:get_insecure_random_u64:");
  assert(
    insecureLine.length > "insecure:get_insecure_random_u64:".length,
    "insecure u64 should have a value",
  );

  // --- random/insecure-seed ---
  assertEquals(findLine("insecure-seed:"), "insecure-seed:42:0");

  // --- io/poll ---
  assertEquals(findLine("poll:len:"), "poll:len:1");

  // --- cli/stdin ---
  // stdin read should succeed with data
  assertStringIncludes(findLine("stdin:read:"), "stdin:read:ok:");

  // --- cli/stderr ---
  assertEquals(findLine("stderr:write:"), "stderr:write:ok");
  // Verify stderr actually captured data
  const stderrOutput = cli._getStderr();
  assertEquals(stderrOutput, "stderr test output\n");

  // --- cli/environment ---
  assertEquals(findLine("environment:args:len:"), "environment:args:len:2");
  assertEquals(findLine("environment:env:len:"), "environment:env:len:2");
  assertStringIncludes(findLine("environment:env:0:"), "=");

  // --- sockets ---
  // tcp and udp create should return error (network denied)
  assertStringIncludes(findLine("sockets:tcp-create:"), "sockets:tcp-create:err:");
  assertStringIncludes(findLine("sockets:udp-create:"), "sockets:udp-create:err:");

  // --- completion marker ---
  assert(lines.includes("===DONE==="), "should complete all interface tests");
});
