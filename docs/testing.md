# Testing

`check.bat` is the authoritative, everliving integration harness. It starts the real
local API server, runs real HTTP checks against the endpoints that exist, performs
a large-payload upload/download with byte-for-byte integrity verification, and
asserts 404s for unknown download tokens. As new endpoints are added, this script
is updated to cover them.

It reads `API_PORT` from `.env` to decide which port to use.

Run it with:

```bash
bun run check
```
