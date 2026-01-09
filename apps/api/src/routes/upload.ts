import { mkdir, rename, unlink } from "node:fs/promises";
import { Buffer } from "node:buffer";
import type { Route } from "./types";
import { normalizeFileExtension } from "../content_type";
import { errorResponse } from "../errors";
import { appendIndexEntry, storagePaths, tokenToStorage, type StoredRecord } from "../storage";

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

const supportedSanitizeTypes = new Set(["image/jpeg", "image/png"]);

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

const parseStripImageMetadata = () => {
  const raw = process.env.PARCEL_STRIP_IMAGE_METADATA;
  if (!raw) {
    throw new Error("[api] PARCEL_STRIP_IMAGE_METADATA is required");
  }
  if (raw !== "0" && raw !== "1") {
    throw new Error("[api] PARCEL_STRIP_IMAGE_METADATA must be 0 or 1");
  }
  return raw === "1";
};

const maxUploadBytes = parseMaxUploadBytes();
const stripImageMetadata = parseStripImageMetadata();

const getContentType = (raw: string | null) => {
  if (!raw) return null;
  const value = raw.split(";")[0]?.trim().toLowerCase();
  return value || null;
};

const extractExtensionFromName = (name: string) => {
  const normalized = name.replace(/\\/g, "/");
  const base = normalized.split("/").pop() ?? "";
  const dotIndex = base.lastIndexOf(".");
  if (dotIndex <= 0 || dotIndex === base.length - 1) return null;
  const candidate = base.slice(dotIndex + 1);
  return normalizeFileExtension(candidate);
};

const safeUnlink = async (path: string | null) => {
  if (!path) return;
  try {
    await unlink(path);
  } catch {}
};

const streamToFile = async (
  filePath: string,
  body: ReadableStream<Uint8Array>,
  maxBytes: number,
) => {
  const targetFile = Bun.file(filePath);
  const sink = targetFile.writer();
  const reader = body.getReader();
  let bytesWritten = 0;
  let tooLarge = false;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        const nextBytes = bytesWritten + value.byteLength;
        if (maxBytes > 0 && nextBytes > maxBytes) {
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
    throw error;
  }

  return { bytesWritten, tooLarge };
};

const stripPngMetadata = (input: Uint8Array) => {
  const data = Buffer.from(input);
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (data.length < signature.length || !data.subarray(0, signature.length).equals(signature)) {
    throw new Error("invalid_png");
  }

  const chunks: Buffer[] = [signature];
  let offset = signature.length;
  while (offset + 8 <= data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.subarray(offset + 4, offset + 8);
    const total = 12 + length;
    if (offset + total > data.length) {
      throw new Error("invalid_png");
    }
    const firstType = type[0];
    if (firstType === undefined) {
      throw new Error("invalid_png");
    }
    const isCritical = firstType >= 65 && firstType <= 90;
    if (isCritical) {
      chunks.push(data.subarray(offset, offset + total));
    }
    const typeLabel = type.toString("ascii");
    offset += total;
    if (typeLabel === "IEND") break;
  }

  return Buffer.concat(chunks);
};

const stripJpegMetadata = (input: Uint8Array) => {
  const data = Buffer.from(input);
  if (data.length < 4 || data[0] !== 0xff || data[1] !== 0xd8) {
    throw new Error("invalid_jpeg");
  }

  const chunks: Buffer[] = [data.subarray(0, 2)];
  let offset = 2;
  while (offset < data.length) {
    if (data[offset] !== 0xff) {
      throw new Error("invalid_jpeg");
    }
    if (offset + 1 >= data.length) {
      throw new Error("invalid_jpeg");
    }
    const marker = data[offset + 1];
    if (marker === undefined) {
      throw new Error("invalid_jpeg");
    }
    if (marker === 0xd9) {
      chunks.push(data.subarray(offset, offset + 2));
      return Buffer.concat(chunks);
    }
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      chunks.push(data.subarray(offset, offset + 2));
      offset += 2;
      continue;
    }
    if (marker === 0xda) {
      if (offset + 4 > data.length) {
        throw new Error("invalid_jpeg");
      }
      const length = data.readUInt16BE(offset + 2);
      const segmentEnd = offset + 2 + length;
      if (segmentEnd > data.length) {
        throw new Error("invalid_jpeg");
      }
      chunks.push(data.subarray(offset, segmentEnd));
      chunks.push(data.subarray(segmentEnd));
      return Buffer.concat(chunks);
    }
    if (offset + 4 > data.length) {
      throw new Error("invalid_jpeg");
    }
    const length = data.readUInt16BE(offset + 2);
    const segmentEnd = offset + 2 + length;
    if (segmentEnd > data.length) {
      throw new Error("invalid_jpeg");
    }
    const isMetadata = marker === 0xfe || (marker >= 0xe0 && marker <= 0xef);
    if (!isMetadata) {
      chunks.push(data.subarray(offset, segmentEnd));
    }
    offset = segmentEnd;
  }

  return Buffer.concat(chunks);
};

const sanitizeImage = (contentType: string, input: Uint8Array) => {
  if (contentType === "image/png") {
    return stripPngMetadata(input);
  }
  if (contentType === "image/jpeg") {
    return stripJpegMetadata(input);
  }
  throw new Error("unsupported_type");
};

const moveTempToFinal = async (tempPath: string, finalPath: string) => {
  try {
    await rename(tempPath, finalPath);
  } catch {
    await Bun.write(finalPath, Bun.file(tempPath));
    await safeUnlink(tempPath);
  }
};

const handleUpload = async (req: Request) => {
  if (!req.body) {
    return errorResponse(400, "bad_request");
  }

  const contentTypeHeader = req.headers.get("content-type") ?? "";
  if (!contentTypeHeader.toLowerCase().startsWith("multipart/form-data")) {
    return errorResponse(400, "bad_request");
  }

  let uploadFile: File | null = null;
  try {
    const form = await req.formData();
    const field = form.get("file");
    if (field instanceof File) {
      uploadFile = field;
    }
  } catch {
    return errorResponse(400, "bad_request");
  }

  if (!uploadFile) {
    return errorResponse(400, "bad_request");
  }

  const fileExtension = extractExtensionFromName(uploadFile.name);
  if (!fileExtension) {
    return errorResponse(400, "bad_request");
  }

  let token = randomToken();
  while (tokenToStorage.has(token)) {
    token = randomToken();
  }

  let storageId = randomStorageId();
  let filePath = storagePaths.uploadPath(storageId, fileExtension);
  while (await Bun.file(filePath).exists()) {
    storageId = randomStorageId();
    filePath = storagePaths.uploadPath(storageId, fileExtension);
  }

  await mkdir(storagePaths.uploadsDir, { recursive: true });
  const contentType = getContentType(uploadFile.type);
  const canSanitize =
    stripImageMetadata && contentType !== null && supportedSanitizeTypes.has(contentType);
  const tempPath = canSanitize ? `${filePath}.tmp` : null;
  const writePath = tempPath ?? filePath;
  let bytesWritten = 0;
  let tooLarge = false;

  try {
    const streamed = await streamToFile(writePath, uploadFile.stream(), maxUploadBytes);
    bytesWritten = streamed.bytesWritten;
    tooLarge = streamed.tooLarge;
  } catch {
    await safeUnlink(writePath);
    return errorResponse(500, "internal_error");
  }

  if (tooLarge) {
    await safeUnlink(writePath);
    return errorResponse(413, "payload_too_large");
  }

  let sanitized = false;
  let sanitizeReason: StoredRecord["sanitizeReason"] = "disabled";
  let sanitizeError: string | null = null;
  let finalByteSize = bytesWritten;

  if (stripImageMetadata) {
    if (canSanitize && tempPath) {
      try {
        const input = new Uint8Array(await Bun.file(tempPath).arrayBuffer());
        const output = sanitizeImage(contentType ?? "", input);
        await Bun.write(filePath, output);
        await safeUnlink(tempPath);
        sanitized = true;
        sanitizeReason = "applied";
        finalByteSize = output.byteLength;
      } catch {
        sanitizeReason = "failed";
        sanitizeError = "sanitize_failed";
        try {
          await moveTempToFinal(tempPath, filePath);
        } catch {
          await safeUnlink(tempPath);
          await safeUnlink(filePath);
          return errorResponse(500, "internal_error");
        }
      }
    } else {
      sanitizeReason = "unsupported_type";
    }
  } else {
    sanitizeReason = "disabled";
  }

  try {
    const record: StoredRecord = {
      token,
      storageId,
      createdAt: new Date().toISOString(),
      byteSize: finalByteSize,
      contentType,
      fileExtension,
      uploadComplete: true,
      sanitized,
      sanitizeReason,
      sanitizeError,
    };
    await appendIndexEntry(record);
    tokenToStorage.set(token, record);
  } catch {
    await safeUnlink(filePath);
    return errorResponse(500, "internal_error");
  }

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
