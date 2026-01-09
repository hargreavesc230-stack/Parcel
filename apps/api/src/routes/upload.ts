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

const parseMaxUploadBytes = () => {
  const raw = process.env.MAX_UPLOAD_SIZE;
  if (!raw) {
    throw new Error("[api] MAX_UPLOAD_SIZE is required");
  }
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error("[api] MAX_UPLOAD_SIZE must be a non-negative number");
  }
  return Math.floor(value);
};

const maxUploadBytes = parseMaxUploadBytes();

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
  let bytesWritten = 0;
  let tooLarge = false;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        const nextBytes = bytesWritten + value.byteLength;
        if (maxUploadBytes > 0 && nextBytes > maxUploadBytes) {
          tooLarge = true;
          await reader.cancel();
          break;
        }
        sink.write(value);
        bytesWritten = nextBytes;
      }
    }
    await sink.end();
  } catch (error) {
    try {
      await sink.end(error instanceof Error ? error : undefined);
    } catch {}
    try {
      await unlink(filePath);
    } catch {}
    return new Response("Internal Server Error", { status: 500 });
  }

  if (tooLarge) {
    try {
      await unlink(filePath);
    } catch {
      return new Response("Internal Server Error", { status: 500 });
    }
    return new Response("Payload Too Large", { status: 413 });
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
