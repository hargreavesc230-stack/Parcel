# parcel

To install dependencies:

```bash
bun install
```

To run the API:

```bash
bun run dev:api
```

To run checks (server is started manually):

```bash
bun run check
```

Existing endpoints:

- `GET /health` -> `ok`
- `POST /upload` -> returns JSON `{ "token": "..." }`
- `GET /download/{token}` -> streams stored bytes
- `GET /inspect/{token}` -> returns safe metadata fields

Tokens are durable across restarts via an append-only `DATA_DIR/index.jsonl`
file, and token collisions are handled by regenerating until unique.

`GET /inspect/{token}` returns:

- `created_at`
- `byte_size`
- `content_type`
- `upload_complete`
- `sanitized`
- `sanitize_reason`
- `sanitize_error`

`MAX_UPLOAD_SIZE` controls the maximum upload size in bytes. Set `0` for
unlimited.

`PARCEL_STRIP_IMAGE_METADATA` controls best-effort metadata stripping for
`image/jpeg` and `image/png` uploads only. Unsupported types are stored as-is,
and sanitization can fail without losing the upload.
