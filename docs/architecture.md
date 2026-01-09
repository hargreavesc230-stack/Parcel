# Architecture

Parcel is API-first, streaming-first, and disk-backed. Uploads are accepted via
`POST /upload` and the request body is streamed directly to disk.

Access is link-only: the server returns a cryptographically random token after
upload. The token is the only thing exposed to the client. No accounts, sessions,
or user identity exist.

Uploads are stored using opaque, server-generated identifiers that are not derived
from content. The token-to-storage mapping is kept in memory for now (alpha).
