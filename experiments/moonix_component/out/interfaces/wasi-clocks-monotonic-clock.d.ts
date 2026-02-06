/** @module Interface wasi:clocks/monotonic-clock@0.2.9 **/
export function now(): Instant;
export function resolution(): Duration;
export function subscribeDuration(when: Duration): Pollable;
export type Duration = bigint;
export type Pollable = import('./wasi-io-poll.js').Pollable;
export type Instant = bigint;
