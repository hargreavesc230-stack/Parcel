# Storage Model

Parcel stores uploads on disk under the operator-controlled base directory set
by `DATA_DIR`, with a fixed layout:

```
DATA_DIR/
  index.jsonl
  uploads/
    <opaque-id-1>
    <opaque-id-2>
```

`DATA_DIR/uploads/` contains only raw file bytes. Filenames are server-generated,
opaque identifiers with the file extension extracted from the uploaded filename
(multipart). The original filename is never stored. Tokens are
separate, user-facing identifiers and are never used as filenames or paths.

`DATA_DIR/index.jsonl` is append-only. Each line is JSON with the minimal
metadata the server creates:

- `token`
- `storage_id` (internal only; never exposed)
- `created_at`
- `byte_size`
- `content_type`
- `file_extension` (from the uploaded filename extension)
- `upload_complete`
- `sanitized`
- `sanitize_reason`
- `sanitize_error`

Forbidden metadata (never stored):

- IP addresses or user agents
- client filenames
- hashes
- internal paths
- download counts

Tokens persist across restarts: the server loads `index.jsonl` at startup into
memory and fails fast on malformed JSON or duplicate tokens. Token collisions
are handled by regenerating until a unique token is produced.

`MAX_UPLOAD_SIZE` enforces a maximum upload size in bytes. When a request exceeds
the limit, the server aborts the stream, deletes the partial file, and does not
append to `index.jsonl`.

Metadata stripping is optional and best-effort for supported image types only.
When `PARCEL_STRIP_IMAGE_METADATA=1`, the server attempts to remove metadata for
`image/jpeg` and `image/png` uploads by re-encoding and dropping ancillary data.
Unsupported types are stored as-is. If sanitization fails, the original bytes
are preserved and `sanitize_reason` is set to `failed` with
`sanitize_error="sanitize_failed"`.

Older index entries that predate these fields are loaded with safe defaults:
`byte_size=null`, `content_type=null`, `upload_complete=true`, `sanitized=false`,
`sanitize_reason="unknown"`, `sanitize_error=null`.
