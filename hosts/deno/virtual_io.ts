/**
 * Virtual I/O streams for jco-transpiled WASIp2 components.
 * Browser-compatible, handler-based InputStream/OutputStream.
 */

let _nextId = 0;

const symbolDispose = Symbol.dispose || Symbol.for("dispose");

// deno-lint-ignore no-unused-vars
export class InputStream {
  id: number;
  handler: {
    read?: (len: bigint) => Uint8Array;
    blockingRead: (len: bigint) => Uint8Array;
    skip?: (len: bigint) => bigint;
    blockingSkip?: (len: bigint) => bigint;
    drop?: () => void;
  };

  constructor(handler: {
    read?: (len: bigint) => Uint8Array;
    blockingRead: (len: bigint) => Uint8Array;
    skip?: (len: bigint) => bigint;
    blockingSkip?: (len: bigint) => bigint;
    drop?: () => void;
  }) {
    this.id = ++_nextId;
    this.handler = handler;
  }

  read(len: bigint): Uint8Array {
    if (this.handler.read) return this.handler.read(len);
    return this.handler.blockingRead(len);
  }

  blockingRead(len: bigint): Uint8Array {
    return this.handler.blockingRead(len);
  }

  skip(len: bigint): bigint {
    if (this.handler.skip) return this.handler.skip(len);
    const bytes = this.read(len);
    return BigInt(bytes.byteLength);
  }

  blockingSkip(len: bigint): bigint {
    if (this.handler.blockingSkip) return this.handler.blockingSkip(len);
    const bytes = this.handler.blockingRead(len);
    return BigInt(bytes.byteLength);
  }

  subscribe() {
    return {};
  }

  [symbolDispose]() {
    if (this.handler.drop) this.handler.drop();
  }
}

// deno-lint-ignore no-unused-vars
export class OutputStream {
  id: number;
  open: boolean;
  handler: {
    write: (buf: Uint8Array) => void;
    checkWrite?: () => bigint;
    flush?: () => void;
    drop?: () => void;
  };

  constructor(handler: {
    write: (buf: Uint8Array) => void;
    checkWrite?: () => bigint;
    flush?: () => void;
    drop?: () => void;
  }) {
    this.id = ++_nextId;
    this.open = true;
    this.handler = handler;
  }

  checkWrite(): bigint {
    if (this.handler.checkWrite) return this.handler.checkWrite();
    return 1_000_000n;
  }

  write(buf: Uint8Array): void {
    this.handler.write(buf);
  }

  blockingWriteAndFlush(buf: Uint8Array): void {
    this.handler.write(buf);
  }

  flush(): void {
    if (this.handler.flush) this.handler.flush();
  }

  blockingFlush(): void {
    this.open = true;
  }

  writeZeroes(len: bigint): void {
    this.write(new Uint8Array(Number(len)));
  }

  blockingWriteZeroesAndFlush(len: bigint): void {
    this.blockingWriteAndFlush(new Uint8Array(Number(len)));
  }

  subscribe() {
    return {};
  }

  [symbolDispose]() {
    if (this.handler.drop) this.handler.drop();
  }
}

const _Error = globalThis.Error;

export class IoError extends _Error {
  payload: string;
  constructor(payload: string) {
    super(payload);
    this.payload = payload;
  }
  toDebugString(): string {
    return this.message;
  }
}

// Named exports matching preview2-shim's io module structure
export const streams = { InputStream, OutputStream };
export const error = { Error: IoError };
