# Testing

`check.bat` is the authoritative, everliving integration harness. It expects
the real API server to already be running and runs real HTTP checks against the
endpoints that exist.

Current coverage:

- `GET /health` readiness
- `POST /upload` as multipart/form-data with a deterministic payload
- `GET /download/{token}` and byte-for-byte integrity check
- `GET /inspect/{token}` with validation of required safe fields
- Image sanitization behavior based on current `PARCEL_STRIP_IMAGE_METADATA`
- Error normalization (status, JSON shape, and content-type) for upload, download, and inspect
- Token reuse
- Upload size limit behavior with 413 and cleanup checks (when `MAX_UPLOAD_SIZE` > 0)

The script reads `API_PORT`, `DATA_DIR`, `MAX_UPLOAD_SIZE`, and
`PARCEL_STRIP_IMAGE_METADATA` from `.env` for logging and payload sizing, and
validates sanitization behavior for the current server setting. The large
payload defaults to 1MB; if `MAX_UPLOAD_SIZE` is smaller, the script scales the
payload down to the configured limit. The 413 test is skipped when
`MAX_UPLOAD_SIZE=0`.

The script does not delete `DATA_DIR` or `DATA_DIR/uploads`; test artifacts may
remain on disk.

Run it with:

```bash
bun run check
```
