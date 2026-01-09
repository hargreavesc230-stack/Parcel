# parcel

To install dependencies:

```bash
bun install
```

To run the API:

```bash
bun run dev:api
```

To run checks (script starts and stops the server):

```bash
bun run check
```

Existing endpoint:

- `GET /health` -> `ok`
- `POST /upload` -> returns JSON `{ "token": "..." }`
- `GET /download/{token}` -> streams stored bytes

Tokens are durable across restarts via an append-only `data/index.jsonl` file, and
token collisions are handled by regenerating until unique.
