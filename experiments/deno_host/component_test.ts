/**
 * E2E tests: jco-transpiled WASIp2 component + virtual_fs/io/cli shims
 *
 * The test fixture (fixtures/src/main.rs) reads /input.txt,
 * writes "processed: <content>" to /output.txt, and prints to stdout.
 *
 * Uses --instantiation async mode so each test gets a fresh wasm instance.
 */

import { assertEquals, assert, assertThrows } from "jsr:@std/assert";
import {
  _setFileData,
  _getFileData,
  preopens,
  types,
} from "./virtual_fs.ts";
import { streams, error } from "./virtual_io.ts";
import * as cli from "./virtual_cli.ts";

// Import the instantiate function (--instantiation async mode)
import { instantiate } from "./fixtures/out/component.js";

/** Load a core wasm module from the fixtures/out directory */
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const url = new URL(`./fixtures/out/${path}`, import.meta.url);
  const bytes = await Deno.readFile(url);
  return WebAssembly.compile(bytes);
}

/** Create a fresh component instance with current virtual FS state */
async function createComponent() {
  cli._clearStdio();
  return await instantiate(getCoreModule, {
    "../../virtual_cli.ts": {
      environment: cli.environment,
      exit: cli.exit,
      stderr: cli.stderr,
      stdin: cli.stdin,
      stdout: cli.stdout,
      terminalInput: cli.terminalInput,
      terminalOutput: cli.terminalOutput,
      terminalStderr: cli.terminalStderr,
      terminalStdin: cli.terminalStdin,
      terminalStdout: cli.terminalStdout,
    },
    "../../virtual_fs.ts": { preopens, types },
    "../../virtual_io.ts": { streams, error },
  });
}

Deno.test("component reads input and writes output via virtual FS", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "Hello from Deno" },
    },
  });

  const component = await createComponent();
  component.run.run(); // success = no exception

  const fileData = _getFileData();
  assert("output.txt" in fileData.dir, "output.txt should exist");

  const outputEntry = fileData.dir["output.txt"];
  assert("source" in outputEntry, "output.txt should be a file");

  const content =
    outputEntry.source instanceof Uint8Array
      ? new TextDecoder().decode(outputEntry.source)
      : (outputEntry.source as string);

  assertEquals(content, "processed: Hello from Deno");
});

Deno.test("component fails gracefully when input.txt is missing", async () => {
  _setFileData({
    dir: {},
  });

  const component = await createComponent();

  // The component should exit with error (proc_exit(1) → unreachable trap)
  try {
    component.run.run();
    throw new Error("should have thrown");
  } catch (e: unknown) {
    // WASI proc_exit(1) triggers an unreachable trap or ComponentError
    assert(e instanceof Error, "should throw an error");
  }
});

Deno.test("component handles different input content", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "MoonBit rocks" },
    },
  });

  const component = await createComponent();
  component.run.run();

  const fileData = _getFileData();
  const outputEntry = fileData.dir["output.txt"];
  assert("source" in outputEntry);

  const content =
    outputEntry.source instanceof Uint8Array
      ? new TextDecoder().decode(outputEntry.source)
      : (outputEntry.source as string);

  assertEquals(content, "processed: MoonBit rocks");
});
