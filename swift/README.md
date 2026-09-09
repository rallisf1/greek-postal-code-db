# Greek Postal Code DB for Swift

An offline, read-only Swift client for Greek postal-code data. It embeds the
SQLite snapshot, supports Linux and Apple platforms, and has no runtime package
dependencies beyond the system SQLite library.

## Requirements

- Swift 6.0 or later
- SQLite development headers and library (`libsqlite3-dev` on Debian/Ubuntu)

## Install

The Swift package manifest is at the monorepo root, as required for remote Git
dependencies. Add the repository to your `Package.swift`:

```swift
.package(url: "https://github.com/rallisf1/greek-postal-code-db.git", from: "0.1.0")
```

Then add `GreekPostalCodeDB` as a dependency of your target.

```swift
import GreekPostalCodeDB

let client = try createPostalCodeClient()
defer { try? client.close() }

let postcode = try client.getPostcode("10431", include: .init(hierarchy: true, streets: true))
let municipalities = try client.searchMunicipalities("Αθην", options: .init(includeHierarchy: true))
```

`getPostcode` returns `nil` for malformed or unknown postcodes. The list and
search APIs return `Entity` values, optionally including official codes and
their hierarchy. `validateAddress(_:)` returns independent statuses per supplied
component; it deliberately does not provide one aggregate validity boolean.

The database is copied to a uniquely named temporary file and opened with
SQLite read-only flags. Calling `close()` releases the SQLite handle and removes
that temporary copy.

## Web support

This package uses SQLite C interop and is intended for Linux and Apple native
platforms. SwiftWasm/browser targets are not supported.
