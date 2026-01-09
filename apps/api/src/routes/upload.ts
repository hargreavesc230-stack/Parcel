import { mkdir } from "node:fs/promises";
import { resolve, join } from "node:path";
import { Buffer } from "node:buffer";
import type { Route } from "./types";
import { tokenToStorage } from "../storage";

const dataRoot = resolve(process.env.DATA_DIR ?? "./data");
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

  const token = randomToken();
  const storageId = randomStorageId();
  const shard = storageId.slice(0, 2);
  const shardDir = join(dataRoot, shard);
  const filePath = join(shardDir, storageId);

  await mkdir(shardDir, { recursive: true });
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

  tokenToStorage.set(token, { storageId, path: filePath });

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
