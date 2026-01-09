import { mkdir, unlink } from "node:fs/promises";
import { Buffer } from "node:buffer";
import type { Route } from "./types";
import { appendIndexEntry, storagePaths, tokenToStorage } from "../storage";

const base64Url = (bytes: Uint8Array) =>
  Buffer.from(bytes)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");

const randomToken = (byteLength = 16) => {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
};

const randomStorageId = (byteLength = 16) => {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return Buffer.from(bytes).toString("hex");
};

const handleUpload = async (req: Request) => {
  if (!req.body) {
    return new Response("Bad Request", { status: 400 });
  }

  let token = randomToken();
  while (tokenToStorage.has(token)) {
    token = randomToken();
  }

  let storageId = randomStorageId();
  let filePath = storagePaths.uploadPath(storageId);
  while (await Bun.file(filePath).exists()) {
    storageId = randomStorageId();
    filePath = storagePaths.uploadPath(storageId);
  }

  await mkdir(storagePaths.uploadsDir, { recursive: true });
  const targetFile = Bun.file(filePath);
  const sink = targetFile.writer();
  const reader = req.body.getReader();

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        sink.write(value);
      }
    }
    await sink.end();
  } catch (error) {
    try {
      await sink.end(error instanceof Error ? error : undefined);
    } catch {}
    return new Response("Internal Server Error", { status: 500 });
  }

  try {
    await appendIndexEntry({ token, storageId, createdAt: new Date().toISOString() });
  } catch (error) {
    try {
      await unlink(filePath);
    } catch {}
    return new Response("Internal Server Error", { status: 500 });
  }

  tokenToStorage.set(token, storageId);

  return new Response(JSON.stringify({ token }), {
    status: 201,
    headers: { "content-type": "application/json" },
  });
};

export const route: Route = {
  method: "POST",
  path: "/upload",
  handle: handleUpload,
};
