import { appendFile, mkdir, readFile } from "node:fs/promises";
import { resolve, join } from "node:path";

export type StoredRecord = {
  token: string;
  storageId: string;
  createdAt: string | null;
  byteSize: number | null;
  contentType: string | null;
  uploadComplete: boolean;
  sanitized: boolean;
  sanitizeReason: "disabled" | "unsupported_type" | "applied" | "failed" | "unknown";
  sanitizeError: string | null;
};

const sanitizeReasons = new Set<StoredRecord["sanitizeReason"]>([
  "disabled",
  "unsupported_type",
  "applied",
  "failed",
  "unknown",
]);

const isSanitizeReason = (value: unknown): value is StoredRecord["sanitizeReason"] =>
  typeof value === "string" && sanitizeReasons.has(value as StoredRecord["sanitizeReason"]);

const dataRootRaw = process.env.DATA_DIR;
if (!dataRootRaw) {
  throw new Error("[api] DATA_DIR is required");
}
const repoRoot = resolve(import.meta.dir, "..", "..", "..");
const dataRoot = resolve(repoRoot, dataRootRaw);
const uploadsDir = join(dataRoot, "uploads");
const indexFile = join(dataRoot, "index.jsonl");

export const tokenToStorage = new Map<string, StoredRecord>();

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

export const appendIndexEntry = async (record: StoredRecord) => {
  const line = JSON.stringify({
    token: record.token,
    storage_id: record.storageId,
    created_at: record.createdAt,
    byte_size: record.byteSize,
    content_type: record.contentType,
    upload_complete: record.uploadComplete,
    sanitized: record.sanitized,
    sanitize_reason: record.sanitizeReason,
    sanitize_error: record.sanitizeError,
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

    const entry = record as {
      token?: unknown;
      storage_id?: unknown;
      created_at?: unknown;
      byte_size?: unknown;
      content_type?: unknown;
      upload_complete?: unknown;
      sanitized?: unknown;
      sanitize_reason?: unknown;
      sanitize_error?: unknown;
    };
    if (typeof entry.token !== "string" || typeof entry.storage_id !== "string") {
      throw new Error(`[api] corrupt index at line ${index + 1}`);
    }

    if (tokenToStorage.has(entry.token)) {
      throw new Error(`[api] duplicate token in index at line ${index + 1}`);
    }

    const stored: StoredRecord = {
      token: entry.token,
      storageId: entry.storage_id,
      createdAt: typeof entry.created_at === "string" ? entry.created_at : null,
      byteSize: typeof entry.byte_size === "number" ? entry.byte_size : null,
      contentType: typeof entry.content_type === "string" ? entry.content_type : null,
      uploadComplete: typeof entry.upload_complete === "boolean" ? entry.upload_complete : true,
      sanitized: typeof entry.sanitized === "boolean" ? entry.sanitized : false,
      sanitizeReason: isSanitizeReason(entry.sanitize_reason) ? entry.sanitize_reason : "unknown",
      sanitizeError: typeof entry.sanitize_error === "string" ? entry.sanitize_error : null,
    };

    tokenToStorage.set(entry.token, stored);
  }
};
