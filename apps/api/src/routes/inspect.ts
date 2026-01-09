import type { Route } from "./types";
import { tokenToStorage } from "../storage";

const handleInspect = (req: Request) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (parts.length !== 2 || parts[0] !== "inspect") {
    return new Response("Not Found", { status: 404 });
  }

  const token = parts[1];
  if (!token) {
    return new Response("Not Found", { status: 404 });
  }

  const record = tokenToStorage.get(token);
  if (!record) {
    return new Response("Not Found", { status: 404 });
  }

  const body = {
    created_at: record.createdAt,
    byte_size: record.byteSize,
    content_type: record.contentType,
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
