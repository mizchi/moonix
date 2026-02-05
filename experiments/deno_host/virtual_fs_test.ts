import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  _clearPreopens,
  _getFileData,
  _setFileData,
  _setPreopens,
  preopens,
  type FileDataDir,
} from "./virtual_fs.ts";

Deno.test("_setFileData creates root preopen", () => {
  _setFileData({ dir: {} });
  const dirs = preopens.getDirectories();
  assertEquals(dirs.length, 1);
  assertEquals(dirs[0][1], "/");
});

Deno.test("Descriptor.getType returns directory for root", () => {
  _setFileData({ dir: {} });
  const [desc] = preopens.getDirectories()[0];
  assertEquals(desc.getType(), "directory");
});

Deno.test("Descriptor.openAt creates file with create flag", () => {
  _setFileData({ dir: {} });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "test.txt", { create: true }, {});
  assertEquals(file.getType(), "regular-file");
});

Deno.test("Descriptor.openAt opens existing file", () => {
  _setFileData({
    dir: {
      "hello.txt": { source: "Hello, World!" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "hello.txt", {}, {});
  assertEquals(file.getType(), "regular-file");
});

Deno.test("Descriptor.read returns file content", () => {
  _setFileData({
    dir: {
      "data.txt": { source: "ABCDE" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "data.txt", {}, {});
  const [data, eof] = file.read(BigInt(10), BigInt(0));
  assertEquals(new TextDecoder().decode(data), "ABCDE");
  assertEquals(eof, true);
});

Deno.test("Descriptor.read with offset", () => {
  _setFileData({
    dir: {
      "data.txt": { source: "ABCDE" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "data.txt", {}, {});
  const [data, eof] = file.read(BigInt(3), BigInt(2));
  assertEquals(new TextDecoder().decode(data), "CDE");
  assertEquals(eof, true);
});

Deno.test("Descriptor.write creates content", () => {
  _setFileData({ dir: {} });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "out.txt", { create: true }, {});

  const content = new TextEncoder().encode("written data");
  file.write(content, BigInt(0));

  const [data] = file.read(BigInt(100), BigInt(0));
  assertEquals(new TextDecoder().decode(data), "written data");
});

Deno.test("Descriptor.stat for file", () => {
  _setFileData({
    dir: {
      "file.txt": { source: "12345" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "file.txt", {}, {});
  const stat = file.stat();
  assertEquals(stat.type, "regular-file");
  assertEquals(stat.size, BigInt(5));
});

Deno.test("Descriptor.stat for directory", () => {
  _setFileData({
    dir: {
      subdir: { dir: {} },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const dir = root.openAt({}, "subdir", {}, {});
  const stat = dir.stat();
  assertEquals(stat.type, "directory");
  assertEquals(stat.size, BigInt(0));
});

Deno.test("Descriptor.readDirectory lists entries", () => {
  _setFileData({
    dir: {
      "b.txt": { source: "" },
      "a.txt": { source: "" },
      subdir: { dir: {} },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const stream = root.readDirectory();

  const entries: { name: string; type: string }[] = [];
  let entry;
  while ((entry = stream.readDirectoryEntry()) !== null) {
    entries.push(entry);
  }

  // BTreeMap-like sorted order
  assertEquals(entries.length, 3);
  assertEquals(entries[0].name, "a.txt");
  assertEquals(entries[0].type, "regular-file");
  assertEquals(entries[1].name, "b.txt");
  assertEquals(entries[2].name, "subdir");
  assertEquals(entries[2].type, "directory");
});

Deno.test("Descriptor.createDirectoryAt", () => {
  _setFileData({ dir: {} });
  const [root] = preopens.getDirectories()[0];
  root.createDirectoryAt("newdir");

  const dir = root.openAt({}, "newdir", {}, {});
  assertEquals(dir.getType(), "directory");
});

Deno.test("Descriptor.unlinkFileAt removes file", () => {
  _setFileData({
    dir: {
      "del.txt": { source: "bye" },
      "keep.txt": { source: "stay" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  root.unlinkFileAt("del.txt");

  // Verify deletion reflected in FileData
  const fd = _getFileData();
  assertEquals("del.txt" in fd.dir, false);
  assertEquals("keep.txt" in fd.dir, true);
});

Deno.test("Descriptor.removeDirectoryAt removes empty dir", () => {
  _setFileData({
    dir: {
      emptydir: { dir: {} },
    },
  });
  const [root] = preopens.getDirectories()[0];
  root.removeDirectoryAt("emptydir");

  const fd = _getFileData();
  assertEquals("emptydir" in fd.dir, false);
});

Deno.test("Descriptor.removeDirectoryAt throws on non-empty", () => {
  _setFileData({
    dir: {
      fulldir: { dir: { "f.txt": { source: "" } } },
    },
  });
  const [root] = preopens.getDirectories()[0];
  try {
    root.removeDirectoryAt("fulldir");
    throw new Error("should have thrown");
  } catch (e) {
    assertEquals(e, "not-empty");
  }
});

Deno.test("readViaStream reads sequentially", () => {
  _setFileData({
    dir: {
      "stream.txt": { source: "ABCDEFGHIJ" },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "stream.txt", {}, {});
  const stream = file.readViaStream(BigInt(0));

  const chunk1 = stream.blockingRead(BigInt(5));
  assertEquals(new TextDecoder().decode(chunk1), "ABCDE");

  const chunk2 = stream.blockingRead(BigInt(5));
  assertEquals(new TextDecoder().decode(chunk2), "FGHIJ");

  // EOF
  try {
    stream.blockingRead(BigInt(1));
    throw new Error("should have thrown");
  } catch (e: unknown) {
    assertEquals((e as { tag: string }).tag, "closed");
  }
});

Deno.test("writeViaStream writes sequentially", () => {
  _setFileData({ dir: {} });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "out.txt", { create: true }, {});
  const stream = file.writeViaStream(BigInt(0));

  stream.write(new TextEncoder().encode("Hello"));
  stream.write(new TextEncoder().encode(" World"));

  const [data] = file.read(BigInt(100), BigInt(0));
  assertEquals(new TextDecoder().decode(data), "Hello World");
});

Deno.test("_setPreopens with multiple mount points", () => {
  _setPreopens({
    "/": { dir: { "root.txt": { source: "root" } } },
    "/data": { dir: { "data.txt": { source: "data" } } },
  });

  const dirs = preopens.getDirectories();
  assertEquals(dirs.length, 2);
  assertEquals(dirs[0][1], "/");
  assertEquals(dirs[1][1], "/data");
});

Deno.test("_clearPreopens removes all", () => {
  _setFileData({ dir: {} });
  _clearPreopens();
  assertEquals(preopens.getDirectories().length, 0);
});

Deno.test("nested directory traversal", () => {
  _setFileData({
    dir: {
      a: {
        dir: {
          b: {
            dir: {
              "deep.txt": { source: "found" },
            },
          },
        },
      },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const file = root.openAt({}, "a/b/deep.txt", {}, {});
  const [data] = file.read(BigInt(100), BigInt(0));
  assertEquals(new TextDecoder().decode(data), "found");
});

Deno.test("statAt through descriptor", () => {
  _setFileData({
    dir: {
      sub: {
        dir: {
          "file.bin": { source: new Uint8Array([1, 2, 3]) },
        },
      },
    },
  });
  const [root] = preopens.getDirectories()[0];
  const stat = root.statAt({}, "sub/file.bin");
  assertEquals(stat.type, "regular-file");
  assertEquals(stat.size, BigInt(3));
});
