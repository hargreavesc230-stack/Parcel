# Storage Model

Parcel stores uploads on disk under an operator-controlled base directory set by
`DATA_DIR`, with a fixed layout:

```
DATA_DIR/
├─ index.jsonl
└─ uploads/
   ├─ <opaque-id-1>
   └─ <opaque-id-2>
```

Each upload is written to a server-generated, opaque storage identifier inside
`DATA_DIR/uploads/`. The `DATA_DIR/index.jsonl` file is append-only and records the
mapping from token to storage identifier.

Storage identifiers are not content-addressable, and there is no deduplication.
The token returned to clients is not the storage identifier and is never exposed
as a path.

Downloads resolve the token to a storage identifier in memory and stream bytes
directly from disk.

Token collisions are handled by regenerating until a unique token is produced.
Token-to-storage mappings are loaded from the on-disk index at startup, so tokens
are durable across restarts.

If an upload exceeds `MAX_UPLOAD_SIZE`, the server aborts the stream, deletes
the partial file, and does not append to the index.
