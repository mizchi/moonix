/** @module Interface wasi:sockets/network@0.2.9 **/
/**
 * # Variants
 * 
 * ## `"ipv4"`
 * 
 * ## `"ipv6"`
 */
export type IpAddressFamily = 'ipv4' | 'ipv6';
/**
 * # Variants
 * 
 * ## `"unknown"`
 * 
 * ## `"access-denied"`
 * 
 * ## `"not-supported"`
 * 
 * ## `"invalid-argument"`
 * 
 * ## `"out-of-memory"`
 * 
 * ## `"timeout"`
 * 
 * ## `"concurrency-conflict"`
 * 
 * ## `"not-in-progress"`
 * 
 * ## `"would-block"`
 * 
 * ## `"invalid-state"`
 * 
 * ## `"new-socket-limit"`
 * 
 * ## `"address-not-bindable"`
 * 
 * ## `"address-in-use"`
 * 
 * ## `"remote-unreachable"`
 * 
 * ## `"connection-refused"`
 * 
 * ## `"connection-reset"`
 * 
 * ## `"connection-aborted"`
 * 
 * ## `"datagram-too-large"`
 * 
 * ## `"name-unresolvable"`
 * 
 * ## `"temporary-resolver-failure"`
 * 
 * ## `"permanent-resolver-failure"`
 */
export type ErrorCode = 'unknown' | 'access-denied' | 'not-supported' | 'invalid-argument' | 'out-of-memory' | 'timeout' | 'concurrency-conflict' | 'not-in-progress' | 'would-block' | 'invalid-state' | 'new-socket-limit' | 'address-not-bindable' | 'address-in-use' | 'remote-unreachable' | 'connection-refused' | 'connection-reset' | 'connection-aborted' | 'datagram-too-large' | 'name-unresolvable' | 'temporary-resolver-failure' | 'permanent-resolver-failure';
