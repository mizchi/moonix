/**
 * E2E tests: MoonBit Shell WASI component + virtual WASI shims
 *
 * The shell component reads commands from stdin and executes them,
 * writing output to stdout via WASI streams.
 *
 * Uses --instantiation async mode so each test gets a fresh wasm instance.
 */

import { assertEquals, assert, assertStringIncludes } from "jsr:@std/assert";
import {
  _setFileData,
  _getFileData,
  preopens,
  types,
} from "./virtual_fs.ts";
import { streams, error } from "./virtual_io.ts";
import * as cli from "./virtual_cli.ts";

// Import the instantiate function from moonix_shell transpiled output
import { instantiate } from "../moonix_shell/out/component.js";

/** Load a core wasm module from the moonix_shell/out directory */
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const url = new URL(`../moonix_shell/out/${path}`, import.meta.url);
  const bytes = await Deno.readFile(url);
  return WebAssembly.compile(bytes);
}

/** Create a fresh component instance with all virtual WASI imports */
async function createComponent() {
  cli._clearStdio();
  return await instantiate(getCoreModule, {
    "../../deno_host/virtual_cli.ts": {
      environment: cli.environment,
      stderr: cli.stderr,
      stdin: cli.stdin,
      stdout: cli.stdout,
    },
    "../../deno_host/virtual_fs.ts": { preopens, types },
    "../../deno_host/virtual_io.ts": { error, streams },
  });
}

Deno.test("moonix shell executes echo command", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("echo hello world\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "hello world");
});

Deno.test("moonix shell handles empty stdin", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  // Should complete without error
  const stdout = cli._getStdout();
  assertEquals(stdout, "");
});

Deno.test("moonix shell handles mkdir and ls", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("mkdir testdir\ntouch testdir/file.txt\nls testdir\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "file.txt");

  // Verify FS state
  const fd = _getFileData();
  assert("testdir" in fd.dir, "testdir should exist in FS");
  const testdir = fd.dir["testdir"];
  assert("dir" in testdir, "testdir should be a directory");
});

Deno.test("moonix shell handles cat and file I/O", async () => {
  _setFileData({
    dir: {
      "hello.txt": { source: "Hello from virtual FS" },
    },
  });
  cli._setStdin("cat hello.txt\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "Hello from virtual FS");
});

Deno.test("moonix shell handles pwd", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("pwd\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "/");
});

Deno.test("moonix shell handles multiple commands", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("echo first\necho second\necho third\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "first");
  assertStringIncludes(stdout, "second");
  assertStringIncludes(stdout, "third");
});

Deno.test("moonix shell handles environment variables", async () => {
  _setFileData({ dir: {} });
  cli._setStdin("env\n");
  cli._setEnvironment({ MY_VAR: "hello", ANOTHER: "world" });
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "MY_VAR=hello");
  assertStringIncludes(stdout, "ANOTHER=world");
});
