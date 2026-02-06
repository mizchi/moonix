/**
 * Virtual poll shim for jco-transpiled WASIp2 components.
 * All pollables are immediately ready (synchronous execution).
 */

export class Pollable {
  ready(): boolean {
    return true;
  }
  block(): void {
    // no-op: always ready
  }
  [Symbol.dispose](): void {
    // no-op
  }
}

export const poll = {
  Pollable,
  poll(list: Pollable[]): Uint32Array {
    // All pollables are ready; return all indices
    const result = new Uint32Array(list.length);
    for (let i = 0; i < list.length; i++) {
      result[i] = i;
    }
    return result;
  },
};
