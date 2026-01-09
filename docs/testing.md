# Testing

`check.bat` is the authoritative, everliving integration harness. It assumes the real
local API server is already running and runs real HTTP checks against the endpoints
that exist, including streaming upload tests that write to disk. As new endpoints are
added, this script is updated to cover them.

It reads `API_PORT` from `.env` to decide which port to use.

Run it with:

```bash
bun run check
```
