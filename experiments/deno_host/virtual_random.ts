/**
 * Virtual random shim for jco-transpiled WASIp2 components.
 * Deterministic RNG based on a simple seed.
 */

let _seed = 42;

function nextByte(): number {
  // Simple xorshift-based PRNG
  _seed ^= _seed << 13;
  _seed ^= _seed >> 17;
  _seed ^= _seed << 5;
  return (_seed >>> 0) & 0xff;
}

export const random = {
  getRandomBytes(len: bigint): Uint8Array {
    const n = Number(len);
    const buf = new Uint8Array(n);
    for (let i = 0; i < n; i++) {
      buf[i] = nextByte();
    }
    return buf;
  },
  getRandomU64(): bigint {
    const bytes = random.getRandomBytes(8n);
    const view = new DataView(bytes.buffer);
    return view.getBigUint64(0, true);
  },
};

export const insecure = {
  getInsecureRandomBytes(len: bigint): Uint8Array {
    return random.getRandomBytes(len);
  },
  getInsecureRandomU64(): bigint {
    return random.getRandomU64();
  },
};

export const insecureSeed = {
  insecureSeed(): [bigint, bigint] {
    return [42n, 0n];
  },
};
