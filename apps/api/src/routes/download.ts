import type { Route } from "./types";
import { tokenToStorage } from "../storage";

const handleDownload = async (req: Request) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);

  if (parts.length !== 2 || parts[0] !== "download") {
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

  const file = Bun.file(record.path);
  if (!(await file.exists())) {
    return new Response("Internal Server Error", { status: 500 });
  }

  const headers = new Headers({ "content-type": "application/octet-stream" });
  if (Number.isFinite(file.size)) {
    headers.set("content-length", String(file.size));
  }

  return new Response(file, { status: 200, headers });
};

export const route: Route = {
  method: "GET",
  path: "/download/:token",
  handle: handleDownload,
};
