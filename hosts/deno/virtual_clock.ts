/**
 * Virtual clock shim for jco-transpiled WASIp2 components.
 * Provides deterministic wall-clock and monotonic-clock.
 */

import { Pollable } from "./virtual_poll.ts";

export const wallClock = {
  now(): { seconds: bigint; nanoseconds: number } {
    return { seconds: 0n, nanoseconds: 0 };
  },
  resolution(): { seconds: bigint; nanoseconds: number } {
    return { seconds: 0n, nanoseconds: 1000000 };
  },
};

export const monotonicClock = {
  now(): bigint {
    return 0n;
  },
  resolution(): bigint {
    return 1000000n;
  },
  subscribeInstant(_when: bigint): Pollable {
    return new Pollable();
  },
  subscribeDuration(_when: bigint): Pollable {
    return new Pollable();
  },
};
