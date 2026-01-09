# Testing

`check.bat` is the authoritative, everliving integration harness. It expects the
real API server to be started manually and runs real HTTP checks against the
endpoints that exist. At the moment it focuses on upload size limit enforcement:
it submits an oversized payload, expects a 413 response, and verifies that index
and uploads counts are unchanged. As new endpoints are added, this script is
updated to cover them.

It reads `API_PORT` and `DATA_DIR` from `.env` to decide which port and data
location to use.

The script does not delete `data/` or `data/uploads/`; test artifacts may remain
on disk.

Run it with:

```bash
bun run check
```
