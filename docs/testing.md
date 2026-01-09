# Testing

`check.bat` is the authoritative, everliving integration harness. It starts the real
local API server, runs real HTTP checks against the endpoints that exist, performs
a large-payload upload/download with byte-for-byte integrity verification, and
asserts 404s for unknown download tokens. It also restarts the server to confirm
token durability, checks token uniqueness across multiple uploads, and validates
the on-disk layout (data/index.jsonl and data/uploads/). As new endpoints are added,
this script is updated to cover them.

It reads `API_PORT` from `.env` to decide which port to use.

The script does not delete `data/` or `data/uploads/`; test artifacts may remain
on disk.

Run it with:

```bash
bun run check
```
