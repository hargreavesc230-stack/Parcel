import type { Route } from "./types";
import { tokenToStorage } from "../storage";
import { errorResponse } from "../errors";

const handleInspect = (req: Request) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (parts.length !== 2 || parts[0] !== "inspect") {
    return errorResponse(404, "not_found");
  }

  const token = parts[1];
  if (!token) {
    return errorResponse(404, "not_found");
  }

  let record;
  try {
    record = tokenToStorage.get(token);
  } catch {
    return errorResponse(500, "internal_error");
  }
  if (!record) {
    return errorResponse(404, "not_found");
  }

  const body = {
    created_at: record.createdAt,
    byte_size: record.byteSize,
    content_type: record.contentType,
    file_extension: record.fileExtension,
    upload_complete: record.uploadComplete,
    sanitized: record.sanitized,
    sanitize_reason: record.sanitizeReason,
    sanitize_error: record.sanitizeError,
  };

  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};

export const route: Route = {
  method: "GET",
  path: "/inspect/:token",
  handle: handleInspect,
};
