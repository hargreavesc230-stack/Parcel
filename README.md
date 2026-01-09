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

Token-to-storage mappings are currently in memory (alpha), so restarts lose tokens.
