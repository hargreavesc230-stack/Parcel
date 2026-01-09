# Architecture

Parcel is API-first, streaming-first, and disk-backed. Implemented endpoints:

- `GET /health`
- `POST /upload`
- `GET /download/{token}`
- `GET /inspect/{token}`

Uploads are streamed to disk under an operator-controlled `DATA_DIR`. Downloads
stream bytes directly from disk. Access is link-only: the server returns a
cryptographically random token after upload, and the token is the only
client-facing identifier. No accounts, sessions, or identity exist.

Tokens are durable across restarts via an append-only `index.jsonl` file loaded
at startup. Token collisions are handled by regenerating until unique.

`POST /upload` honors `MAX_UPLOAD_SIZE`; exceeding the limit returns 413 without
exposing internal paths. When `PARCEL_STRIP_IMAGE_METADATA=1`, the server makes
a best-effort attempt to strip metadata for `image/jpeg` and `image/png` uploads
only. Unsupported types are stored as-is.

`GET /inspect/{token}` returns only the safe metadata fields created by the
server (such as timestamps and byte size). It never exposes storage identifiers
or internal paths.
