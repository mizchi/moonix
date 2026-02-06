/**
 * Virtual filesystem shim for jco-transpiled WASIp2 components.
 *
 * FileData tree structure:
 *   { dir: { "name": FileDataEntry, ... } }  -- directory
 *   { source: Uint8Array | string }           -- file
 *
 * Usage:
 *   import { _setFileData, _getFileData, preopens, types } from "./virtual_fs.ts";
 *   _setFileData({ dir: { "hello.txt": { source: "Hello!" } } });
 */

// Import InputStream/OutputStream from virtual_io so that instanceof checks
// in jco-generated component.js pass correctly (both use the same classes).
import { InputStream, OutputStream } from "./virtual_io.ts";

// --- FileData types ---

export interface FileDataFile {
  source: Uint8Array | string;
}

export interface FileDataDir {
  dir: Record<string, FileDataEntry>;
}

export type FileDataEntry = FileDataFile | FileDataDir;

function isDir(entry: FileDataEntry): entry is FileDataDir {
  return "dir" in entry;
}

function isFile(entry: FileDataEntry): entry is FileDataFile {
  return "source" in entry;
}

// --- State ---

let _fileData: FileDataDir = { dir: {} };
let _cwd = "/";
let _preopens: Array<[Descriptor, string]> = [];

// --- Public configuration API ---

export function _setFileData(fileData: FileDataDir): void {
  _fileData = fileData;
  _preopens = [[new Descriptor(fileData), "/"]];
}

export function _getFileData(): FileDataDir {
  return _fileData;
}

export function _setCwd(cwd: string): void {
  _cwd = cwd;
}

export function _setPreopens(config: Record<string, FileDataDir>): void {
  _preopens = [];
  for (const [virtualPath, fileData] of Object.entries(config)) {
    _preopens.push([new Descriptor(fileData), virtualPath]);
  }
}

export function _addPreopen(virtualPath: string, fileData: FileDataDir): void {
  _preopens.push([new Descriptor(fileData), virtualPath]);
}

export function _clearPreopens(): void {
  _preopens = [];
}

// --- Path resolution ---

function resolvePath(
  parentEntry: FileDataEntry,
  subpath: string,
  openFlags: { create?: boolean; directory?: boolean; truncate?: boolean } = {},
): FileDataEntry {
  let entry = parentEntry;
  const segments = subpath.split("/").filter((s) => s !== "" && s !== ".");

  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    if (segment === "..") throw "no-entry";
    if (!isDir(entry)) throw "not-directory";

    if (!(segment in entry.dir)) {
      if (openFlags.create) {
        // Only create the last segment; intermediate must exist
        if (i === segments.length - 1) {
          entry.dir[segment] = openFlags.directory
            ? { dir: {} }
            : { source: new Uint8Array(0) };
        } else {
          throw "no-entry";
        }
      } else {
        throw "no-entry";
      }
    }
    entry = entry.dir[segment];
  }

  if (openFlags.truncate && isFile(entry)) {
    entry.source = new Uint8Array(0);
  }

  return entry;
}

function getSource(entry: FileDataEntry): Uint8Array {
  if (!isFile(entry)) throw "bad-descriptor";
  if (typeof entry.source === "string") {
    entry.source = new TextEncoder().encode(entry.source);
  }
  return entry.source;
}

// InputStream and OutputStream are imported from preview2-shim above.
// The browser version accepts handler objects with blockingRead/write methods.

// --- DirectoryEntryStream ---

class DirectoryEntryStream {
  #entries: [string, FileDataEntry][];
  #idx = 0;

  constructor(entries: [string, FileDataEntry][]) {
    this.#entries = entries;
  }

  readDirectoryEntry(): { name: string; type: string } | null {
    if (this.#idx >= this.#entries.length) return null;
    const [name, entry] = this.#entries[this.#idx++];
    return { name, type: isDir(entry) ? "directory" : "regular-file" };
  }
}

// --- Descriptor ---

const TIME_ZERO = { seconds: BigInt(0), nanoseconds: 0 };

class Descriptor {
  #entry: FileDataEntry;

  constructor(entry: FileDataEntry) {
    this.#entry = entry;
  }

  readViaStream(offset: bigint) {
    const source = getSource(this.#entry);
    let off = Number(offset);
    return new InputStream({
      blockingRead(len: bigint): Uint8Array {
        if (off >= source.byteLength) throw { tag: "closed" };
        const bytes = source.slice(off, off + Number(len));
        off += bytes.byteLength;
        return bytes;
      },
    });
  }

  writeViaStream(offset: bigint) {
    const entry = this.#entry as FileDataFile;
    let off = Number(offset);
    return new OutputStream({
      write(buf: Uint8Array): void {
        const existing = getSource(entry);
        const newLen = Math.max(off + buf.byteLength, existing.byteLength);
        const newSource = new Uint8Array(newLen);
        newSource.set(existing, 0);
        newSource.set(buf, off);
        off += buf.byteLength;
        entry.source = newSource;
      },
    });
  }

  appendViaStream() {
    return this.writeViaStream(BigInt(getSource(this.#entry).byteLength));
  }

  advise() {}
  syncData() {}

  getFlags() {
    return { read: true, write: true };
  }

  getType(): string {
    if (isDir(this.#entry)) return "directory";
    if (isFile(this.#entry)) return "regular-file";
    return "unknown";
  }

  setSize(size: bigint) {
    const source = getSource(this.#entry);
    const n = Number(size);
    if (n < source.byteLength) {
      (this.#entry as FileDataFile).source = source.slice(0, n);
    } else {
      const newSource = new Uint8Array(n);
      newSource.set(source, 0);
      (this.#entry as FileDataFile).source = newSource;
    }
  }

  setTimes() {}

  read(
    length: bigint,
    offset: bigint,
  ): [Uint8Array, boolean] {
    const source = getSource(this.#entry);
    const off = Number(offset);
    const len = Number(length);
    return [source.slice(off, off + len), off + len >= source.byteLength];
  }

  write(buffer: Uint8Array, offset: bigint): bigint {
    const off = Number(offset);
    const existing = isFile(this.#entry)
      ? getSource(this.#entry)
      : new Uint8Array(0);
    const newLen = Math.max(off + buffer.byteLength, existing.byteLength);
    const newSource = new Uint8Array(newLen);
    newSource.set(existing, 0);
    newSource.set(buffer, off);
    (this.#entry as FileDataFile).source = newSource;
    return BigInt(buffer.byteLength);
  }

  readDirectory(): DirectoryEntryStream {
    if (!isDir(this.#entry)) throw "bad-descriptor";
    const entries = Object.entries(this.#entry.dir).sort(([a], [b]) =>
      a > b ? 1 : -1
    );
    return new DirectoryEntryStream(entries);
  }

  sync() {}

  createDirectoryAt(path: string) {
    resolvePath(this.#entry, path, { create: true, directory: true });
  }

  stat() {
    if (isFile(this.#entry)) {
      return {
        type: "regular-file",
        linkCount: BigInt(0),
        size: BigInt(getSource(this.#entry).byteLength),
        dataAccessTimestamp: TIME_ZERO,
        dataModificationTimestamp: TIME_ZERO,
        statusChangeTimestamp: TIME_ZERO,
      };
    }
    return {
      type: isDir(this.#entry) ? "directory" : "unknown",
      linkCount: BigInt(0),
      size: BigInt(0),
      dataAccessTimestamp: TIME_ZERO,
      dataModificationTimestamp: TIME_ZERO,
      statusChangeTimestamp: TIME_ZERO,
    };
  }

  // deno-lint-ignore no-unused-vars
  statAt(_pathFlags: unknown, path: string) {
    const entry = resolvePath(this.#entry, path);
    if (isFile(entry)) {
      return {
        type: "regular-file",
        linkCount: BigInt(0),
        size: BigInt(getSource(entry).byteLength),
        dataAccessTimestamp: TIME_ZERO,
        dataModificationTimestamp: TIME_ZERO,
        statusChangeTimestamp: TIME_ZERO,
      };
    }
    return {
      type: isDir(entry) ? "directory" : "unknown",
      linkCount: BigInt(0),
      size: BigInt(0),
      dataAccessTimestamp: TIME_ZERO,
      dataModificationTimestamp: TIME_ZERO,
      statusChangeTimestamp: TIME_ZERO,
    };
  }

  setTimesAt() {}
  linkAt() {}

  openAt(
    _pathFlags: unknown,
    path: string,
    openFlags: { create?: boolean; directory?: boolean; truncate?: boolean },
    _descriptorFlags: unknown,
  ): Descriptor {
    return new Descriptor(resolvePath(this.#entry, path, openFlags));
  }

  readlinkAt(): string {
    throw "unsupported";
  }

  removeDirectoryAt(path: string) {
    const segments = path.split("/").filter(Boolean);
    const name = segments.pop()!;
    const parent = segments.length
      ? resolvePath(this.#entry, segments.join("/"))
      : this.#entry;
    if (!isDir(parent)) throw "not-directory";
    const target = parent.dir[name];
    if (!target || !isDir(target)) throw "not-directory";
    if (Object.keys(target.dir).length > 0) throw "not-empty";
    delete parent.dir[name];
  }

  renameAt(
    oldPath: string,
    newDescriptor: Descriptor,
    newPath: string,
  ) {
    const oldSegments = oldPath.split("/").filter(Boolean);
    const oldName = oldSegments.pop()!;
    const oldParent = oldSegments.length
      ? resolvePath(this.#entry, oldSegments.join("/"))
      : this.#entry;
    if (!isDir(oldParent)) throw "not-directory";
    const entry = oldParent.dir[oldName];
    if (!entry) throw "no-entry";

    const newSegments = newPath.split("/").filter(Boolean);
    const newName = newSegments.pop()!;
    const newParent = newSegments.length
      // Access private field via cast - same class
      ? resolvePath(
        (newDescriptor as unknown as { "#entry": FileDataEntry })["#entry"] ??
          newDescriptor.#entry,
        newSegments.join("/"),
      )
      : newDescriptor.#entry;
    if (!isDir(newParent)) throw "not-directory";

    newParent.dir[newName] = entry;
    delete oldParent.dir[oldName];
  }

  symlinkAt() {
    throw "unsupported";
  }

  unlinkFileAt(path: string) {
    const segments = path.split("/").filter(Boolean);
    const name = segments.pop()!;
    const parent = segments.length
      ? resolvePath(this.#entry, segments.join("/"))
      : this.#entry;
    if (!isDir(parent)) throw "not-directory";
    if (!(name in parent.dir)) throw "no-entry";
    if (isDir(parent.dir[name])) throw "is-directory";
    delete parent.dir[name];
  }

  isSameObject(other: Descriptor): boolean {
    return other === this;
  }

  metadataHash() {
    return { upper: BigInt(0), lower: BigInt(0) };
  }

  // deno-lint-ignore no-unused-vars
  metadataHashAt(_pathFlags: unknown, _path: string) {
    return { upper: BigInt(0), lower: BigInt(0) };
  }
}

// --- WASI interface exports ---

export const preopens = {
  getDirectories(): Array<[Descriptor, string]> {
    return _preopens;
  },
};

export const types = {
  Descriptor,
  DirectoryEntryStream,
  filesystemErrorCode(_err: unknown): string {
    return "io";
  },
};

// Initialize with empty root
_setFileData(_fileData);
