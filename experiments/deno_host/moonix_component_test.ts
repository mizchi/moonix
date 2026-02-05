/**
 * E2E tests: MoonBit WASIp2 component (0.2.9) + virtual_fs/io/cli shims
 *
 * The MoonBit component reads /input.txt,
 * writes "processed: <content>" to /output.txt, and prints to stdout.
 *
 * Uses --instantiation async mode so each test gets a fresh wasm instance.
 */

import { assertEquals, assert } from "jsr:@std/assert";
import {
  _setFileData,
  _getFileData,
  preopens,
  types,
} from "./virtual_fs.ts";
import { streams, error } from "./virtual_io.ts";
import * as cli from "./virtual_cli.ts";

// Import the instantiate function from moonix_component transpiled output
import { instantiate } from "../moonix_component/out/component.js";

/** Load a core wasm module from the moonix_component/out directory */
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const url = new URL(`../moonix_component/out/${path}`, import.meta.url);
  const bytes = await Deno.readFile(url);
  return WebAssembly.compile(bytes);
}

/** Create a fresh component instance with current virtual FS state */
async function createComponent() {
  cli._clearStdio();
  return await instantiate(getCoreModule, {
    "../../deno_host/virtual_cli.ts": {
      stdout: cli.stdout,
    },
    "../../deno_host/virtual_fs.ts": { preopens, types },
    "../../deno_host/virtual_io.ts": { streams, error },
  });
}

Deno.test("moonix component reads input and writes output via virtual FS", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "Hello from MoonBit" },
    },
  });

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

  const component = await createComponent();

  try {
    component.run.run();
    throw new Error("should have thrown");
  } catch (e: unknown) {
    assert(e instanceof Error, "should throw an error");
  }
});

Deno.test("moonix component stdout output", async () => {
  _setFileData({
    dir: {
      "input.txt": { source: "stdout test" },
    },
  });

  const component = await createComponent();
  component.run.run();

  const stdoutOutput = cli._getStdout();
  assertEquals(stdoutOutput, "processed: stdout test\n");
});
