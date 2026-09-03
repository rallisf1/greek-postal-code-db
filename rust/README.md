# Greek Postal Code DB for Rust

Offline, read-only Greek postal-code data backed by an embedded SQLite database. The crate uses bundled SQLite, so no system SQLite development package is required.

This crate lives in the `rust/` subdirectory of a monorepo. Until it is published on crates.io, depend on it from Git:

```toml
[dependencies]
greek-postal-code-db = { git = "https://github.com/rallisf1/greek-postal-code-db.git" }
```

```rust
use greek_postal_code_db::{PostalCodeClient, PostcodeOptions};

let client = PostalCodeClient::new()?;
let postcode = client.get_postcode("10431", PostcodeOptions {
    include_hierarchy: true,
    include_streets: true,
})?;
```

`PostalCodeClient` exposes list/search methods for all administrative entities, `get_postcode`, `validate_address`, and `close`. Results are JSON values so optional hierarchy and validation data retain the same shape as the other language clients.
