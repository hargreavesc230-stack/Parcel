# Storage Model

Parcel stores uploads on disk under an operator-controlled base directory (default
`./data`). Each upload is written to a server-generated, opaque storage identifier
and sharded into predictable subdirectories.

Storage identifiers are not content-addressable, and there is no deduplication.
The token returned to clients is not the storage identifier and is never exposed
as a path.

Token-to-storage mappings are currently in memory (alpha).
