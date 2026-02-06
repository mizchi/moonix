/**
 * E2E tests: MoonBit Shell WASI component + virtual WASI shims
 *
 * The shell component uses moonix core MemFs internally.
 * WASI is only used for I/O boundary (stdin/stdout/stderr/environment).
 *
 * Uses --instantiation async mode so each test gets a fresh wasm instance.
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { streams, error } from "../virtual_io.ts";
import * as cli from "../virtual_cli.ts";

// Import the instantiate function from shell component transpiled output
import { instantiate } from "../../../components/shell/out/component.js";

/** Load a core wasm module from the shell/out directory */
async function getCoreModule(path: string): Promise<WebAssembly.Module> {
  const url = new URL(`../../../components/shell/out/${path}`, import.meta.url);
  const bytes = await Deno.readFile(url);
  return WebAssembly.compile(bytes);
}

/** Create a fresh component instance with WASI I/O imports only */
async function createComponent() {
  cli._clearStdio();
  return await instantiate(getCoreModule, {
    "../../hosts/deno/virtual_cli.ts": {
      environment: cli.environment,
      stderr: cli.stderr,
      stdin: cli.stdin,
      stdout: cli.stdout,
    },
    "../../hosts/deno/virtual_io.ts": { error, streams },
  });
}

Deno.test("moonix shell executes echo command", async () => {
  cli._setStdin("echo hello world\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "hello world");
});

Deno.test("moonix shell handles empty stdin", async () => {
  cli._setStdin("");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertEquals(stdout, "");
});

Deno.test("moonix shell handles mkdir and ls (internal MemFs)", async () => {
  // Shell uses internal MemFs, so mkdir/ls work within a single session
  cli._setStdin("mkdir testdir\ntouch testdir/file.txt\nls testdir\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "file.txt");
});

Deno.test("moonix shell handles file I/O (internal MemFs)", async () => {
  // Create file and read it back within same session
  cli._setStdin("echo 'Hello from shell' > hello.txt\ncat hello.txt\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "Hello from shell");
});

Deno.test("moonix shell handles pwd", async () => {
  cli._setStdin("pwd\n");
  cli._setEnvironment({});
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "/");
});

Deno.test("moonix shell handles multiple commands", async () => {
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
  cli._setStdin("env\n");
  cli._setEnvironment({ MY_VAR: "hello", ANOTHER: "world" });
  cli._setArgs([]);

  const component = await createComponent();
  component.run.run();

  const stdout = cli._getStdout();
  assertStringIncludes(stdout, "MY_VAR=hello");
  assertStringIncludes(stdout, "ANOTHER=world");
});
