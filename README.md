# parcel

Parcel is a link-only, anonymous, streaming-first file drop API.

Invariants:

- No accounts, auth, users, sessions, or identity
- No listings, search, or discovery
- Tokens are the only access mechanism

To install dependencies:

```bash
bun install
```

To run the API:

```bash
bun run dev:api
```

To run the web UI:

```bash
bun run dev:web
```

The web dev server proxies `/health`, `/upload`, `/download`, and `/inspect` to
`http://127.0.0.1:8787`, so keep the API running on that port.

To run checks (server must already be running):

```bash
bun run check
```

Existing endpoints:

- `GET /health` -> `ok`
- `POST /upload` -> returns JSON `{ "token": "..." }`
- `GET /download/{token}` -> streams stored bytes
- `GET /inspect/{token}` -> returns safe metadata fields

Non-2xx responses (except `/health`) use `{ "error": "<code>" }` JSON with
`application/json` content-type.

Tokens are durable across restarts via an append-only `DATA_DIR/index.jsonl`
file, and token collisions are handled by regenerating until unique.

`GET /inspect/{token}` returns:

- `created_at`
- `byte_size`
- `content_type`
- `file_extension`
- `upload_complete`
- `sanitized`
- `sanitize_reason`
- `sanitize_error`

`MAX_UPLOAD_SIZE` controls the maximum upload size in bytes. Set `0` for
unlimited.

`PARCEL_STRIP_IMAGE_METADATA` controls best-effort metadata stripping for
`image/jpeg` and `image/png` uploads only. Unsupported types are stored as-is,
and sanitization can fail without losing the upload.

Uploads are `multipart/form-data` with a `file` field. The server keeps only the
file extension from the uploaded filename (no original name is stored).
Downloads use a random filename with the stored extension in the
`Content-Disposition` header.
Uploads without a filename extension are rejected with `bad_request`.

Web UI:

- `/` is a simple landing page.
- `/upload` lets you upload a single file and returns a shareable download URL.
- `/info` explains how Parcel works and the limitations.
- There is no download UI by design.
- The web UI is stateless; copy links immediately or they are lost on refresh.
- The UI is Windows 95/98-inspired.

Limitations:

- Metadata stripping is best-effort and limited to `image/jpeg` and `image/png`
- No content scanning or moderation
- Tokens must be kept secret; possession is the only access control
