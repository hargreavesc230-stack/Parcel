import { appendFile, mkdir, readFile } from "node:fs/promises";
import { resolve, join } from "node:path";

export type TokenRecord = {
  token: string;
  storageId: string;
  createdAt?: string;
};

const dataRootRaw = process.env.DATA_DIR;
if (!dataRootRaw) {
  throw new Error("[api] DATA_DIR is required");
}
const repoRoot = resolve(import.meta.dir, "..", "..", "..");
const dataRoot = resolve(repoRoot, dataRootRaw);
const uploadsDir = join(dataRoot, "uploads");
const indexFile = join(dataRoot, "index.jsonl");

export const tokenToStorage = new Map<string, string>();

export const storagePaths = {
  dataRoot,
  uploadsDir,
  indexFile,
  uploadPath: (storageId: string) => join(uploadsDir, storageId),
};

export const initStorage = async () => {
  await mkdir(uploadsDir, { recursive: true });
  await loadIndex();
};

export const appendIndexEntry = async (record: TokenRecord) => {
  const line = JSON.stringify({
    token: record.token,
    storage_id: record.storageId,
    created_at: record.createdAt,
  });
  await appendFile(indexFile, `${line}\n`, "utf8");
};

const loadIndex = async () => {
  let content = "";
  try {
    content = await readFile(indexFile, "utf8");
  } catch (error) {
    const err = error as NodeJS.ErrnoException;
    if (err && err.code === "ENOENT") {
      return;
    }
    throw error;
  }

  const lines = content.split(/\r?\n/);
  for (const [index, rawLine] of lines.entries()) {
    const line = rawLine.trim();
    if (!line) continue;
    let record: unknown;
    try {
      record = JSON.parse(line);
    } catch {
      throw new Error(`[api] corrupt index at line ${index + 1}`);
    }

    if (!record || typeof record !== "object") {
      throw new Error(`[api] corrupt index at line ${index + 1}`);
    }

    const entry = record as { token?: unknown; storage_id?: unknown };
    if (typeof entry.token !== "string" || typeof entry.storage_id !== "string") {
      throw new Error(`[api] corrupt index at line ${index + 1}`);
    }

    if (tokenToStorage.has(entry.token)) {
      throw new Error(`[api] duplicate token in index at line ${index + 1}`);
    }

    tokenToStorage.set(entry.token, entry.storage_id);
  }
};
