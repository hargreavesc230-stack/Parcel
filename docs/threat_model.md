# Threat Model

Parcel is fully anonymous and link-only. The only client-facing identifier is
the access token returned after upload. There are no accounts, users, sessions,
listing, search, or discovery features.

Anyone with a valid token can access the corresponding content. Token leakage
is a primary risk; operators must treat tokens as secrets and assume possession
grants access. Parcel does not perform content scanning or moderation.

Metadata stripping is best-effort and limited. When enabled, the server only
attempts to remove metadata from `image/jpeg` and `image/png` uploads by
re-encoding and dropping ancillary data. For unsupported content types, files
are stored as-is. Even for supported types, sanitization can fail; in that case
the original bytes are preserved and the metadata fields reflect the failure.

Clients should not assume that all metadata is removed. Operators should treat
uploads as potentially containing embedded metadata unless sanitization is
explicitly enabled and verified for the content type.
