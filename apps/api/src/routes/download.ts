import { Buffer } from "node:buffer";
import type { Route } from "./types";
import { storagePaths, tokenToStorage } from "../storage";
import { errorResponse } from "../errors";

const handleDownload = async (req: Request) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (parts.length !== 2 || parts[0] !== "download") {
    return errorResponse(404, "not_found");
  }

  const token = parts[1];
  if (!token) {
    return errorResponse(404, "not_found");
  }
  const record = tokenToStorage.get(token);
  if (!record) {
    return errorResponse(404, "not_found");
  }

  const filePath = storagePaths.uploadPath(record.storageId, record.fileExtension);
  const file = Bun.file(filePath);
  if (!(await file.exists())) {
    return errorResponse(500, "internal_error");
  }

  const headers = new Headers({ "content-type": "application/octet-stream" });
  const downloadName = randomDownloadName();
  const extension = record.fileExtension ?? "";
  headers.set("content-disposition", `attachment; filename="${downloadName}${extension}"`);
  if (Number.isFinite(file.size)) {
    headers.set("content-length", String(file.size));
  }

  return new Response(file, { status: 200, headers });
};

const randomDownloadName = (byteLength = 12) => {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return Buffer.from(bytes)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
};


export const route: Route = {
  method: "GET",
  path: "/download/:token",
  handle: handleDownload,
};
