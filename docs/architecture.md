# Architecture

Parcel is API-first, streaming-first, and disk-backed. Implemented endpoints:

- `GET /health`
- `POST /upload`
- `GET /download/{token}`
- `GET /inspect/{token}`

Uploads are accepted as multipart form uploads (field `file`) and streamed to
disk under an operator-controlled `DATA_DIR`. The server stores only the file
extension from the uploaded filename, never the original name. Downloads stream
bytes directly from disk. Access is link-only: the server returns a
cryptographically random token after upload, and the token is the only
client-facing identifier. No accounts, sessions, or identity exist.

Uploads without a filename extension are rejected with `bad_request`.

Tokens are durable across restarts via an append-only `index.jsonl` file loaded
at startup. Token collisions are handled by regenerating until unique.

`POST /upload` honors `MAX_UPLOAD_SIZE`; exceeding the limit returns 413 without
exposing internal paths. When `PARCEL_STRIP_IMAGE_METADATA=1`, the server makes
a best-effort attempt to strip metadata for `image/jpeg` and `image/png` uploads
only. Unsupported types are stored as-is.

`GET /inspect/{token}` returns only the safe metadata fields created by the
server: `created_at`, `byte_size`, `content_type`, `file_extension`,
`upload_complete`, `sanitized`, `sanitize_reason`, `sanitize_error`. It never
exposes storage identifiers or internal paths.

All error responses (except `/health`) use a canonical JSON shape:

```
{ "error": "<code>" }
```

Supported error codes are: `bad_request`, `not_found`, `payload_too_large`,
`internal_error`.
