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

Existing endpoint:

- `GET /health` -> `ok`
- `POST /upload` -> returns JSON `{ "token": "..." }`
- `GET /download/{token}` -> streams stored bytes

Tokens are durable across restarts via an append-only `data/index.jsonl` file, and
token collisions are handled by regenerating until unique.

`MAX_UPLOAD_SIZE` controls the maximum upload size in bytes. Set `0` for
unlimited.
