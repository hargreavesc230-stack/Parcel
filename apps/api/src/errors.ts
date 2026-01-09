export type ErrorCode =
  | "bad_request"
  | "not_found"
  | "gone"
  | "payload_too_large"
  | "internal_error";

const errorBody = (code: ErrorCode) => JSON.stringify({ error: code });

export const errorResponse = (status: 400 | 404 | 410 | 413 | 500, code: ErrorCode) =>
  new Response(errorBody(code), {
    status,
    headers: { "content-type": "application/json" },
  });
