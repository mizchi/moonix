/**
 * Virtual CLI shim for jco-transpiled WASIp2 components.
 * Provides stdin/stdout/stderr/exit/environment/terminal stubs.
 */

import { InputStream, OutputStream } from "./virtual_io.ts";

// --- stdout/stderr capture ---

let _stdoutBuf: Uint8Array[] = [];
let _stderrBuf: Uint8Array[] = [];

export function _getStdout(): string {
  const merged = mergeBuffers(_stdoutBuf);
  return new TextDecoder().decode(merged);
}

export function _getStderr(): string {
  const merged = mergeBuffers(_stderrBuf);
  return new TextDecoder().decode(merged);
}

export function _clearStdio(): void {
  _stdoutBuf = [];
  _stderrBuf = [];
}

function mergeBuffers(bufs: Uint8Array[]): Uint8Array {
  const total = bufs.reduce((n, b) => n + b.byteLength, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const b of bufs) {
    out.set(b, off);
    off += b.byteLength;
  }
  return out;
}

// --- stdin ---

let _stdinData = new Uint8Array(0);
let _stdinOffset = 0;

export function _setStdin(data: string | Uint8Array): void {
  _stdinData = typeof data === "string" ? new TextEncoder().encode(data) : data;
  _stdinOffset = 0;
}

export const stdin = {
  getStdin(): InstanceType<typeof InputStream> {
    return new InputStream({
      blockingRead(len: bigint): Uint8Array {
        if (_stdinOffset >= _stdinData.byteLength) throw { tag: "closed" };
        const end = Math.min(_stdinOffset + Number(len), _stdinData.byteLength);
        const bytes = _stdinData.slice(_stdinOffset, end);
        _stdinOffset = end;
        return bytes;
      },
    });
  },
};

// --- stdout ---

export const stdout = {
  getStdout(): InstanceType<typeof OutputStream> {
    return new OutputStream({
      write(buf: Uint8Array): void {
        _stdoutBuf.push(buf.slice());
      },
    });
  },
};

// --- stderr ---

export const stderr = {
  getStderr(): InstanceType<typeof OutputStream> {
    return new OutputStream({
      write(buf: Uint8Array): void {
        _stderrBuf.push(buf.slice());
      },
    });
  },
};

// --- exit ---

class ExitError extends Error {
  code: number;
  constructor(code: number) {
    super(`WASI exit: ${code}`);
    this.code = code;
  }
}

export const exit = {
  exit(status: { tag: string; val?: number }): void {
    if (status.tag === "err") {
      throw new ExitError(status.val ?? 1);
    }
  },
};

// --- environment ---

let _envVars: [string, string][] = [];
let _args: string[] = [];

export function _setEnvironment(vars: Record<string, string>): void {
  _envVars = Object.entries(vars);
}

export function _setArgs(args: string[]): void {
  _args = args;
}

export const environment = {
  getEnvironment(): [string, string][] {
    return _envVars;
  },
  getArguments(): string[] {
    return _args;
  },
};

// --- terminal stubs ---

class TerminalInput {}
class TerminalOutput {}

export const terminalInput = { TerminalInput };
export const terminalOutput = { TerminalOutput };

export const terminalStdin = {
  getTerminalStdin(): undefined {
    return undefined;
  },
};

export const terminalStdout = {
  getTerminalStdout(): undefined {
    return undefined;
  },
};

export const terminalStderr = {
  getTerminalStderr(): undefined {
    return undefined;
  },
};
