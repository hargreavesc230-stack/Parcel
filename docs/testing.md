# Testing

`check.bat` is the authoritative, everliving integration harness. It expects
the real API server to be started manually and runs real HTTP checks against the
endpoints that exist.

Current coverage:

- `GET /health` readiness
- `POST /upload` as multipart/form-data with a deterministic payload
- `GET /download/{token}` and byte-for-byte integrity check
- `GET /inspect/{token}` with validation of required safe fields
- Image sanitization behavior based on current `PARCEL_STRIP_IMAGE_METADATA`

The script reads `API_PORT`, `DATA_DIR`, `MAX_UPLOAD_SIZE`, and
`PARCEL_STRIP_IMAGE_METADATA` from `.env` for logging and payload sizing, and
validates sanitization behavior for the current server setting.

The script does not delete `DATA_DIR` or `DATA_DIR/uploads`; test artifacts may
remain on disk.

Run it with:

```bash
bun run check
```
