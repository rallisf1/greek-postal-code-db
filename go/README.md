# Greek Postal Code DB for Go

Offline, read-only Greek postal-code data for Go. The SQLite database is embedded in the library binary, so no system SQLite installation or CGO toolchain is required.

This is a submodule in a monorepo. Install it using its `go/` path:

```bash
go get github.com/rallisf1/greek-postal-code-db/go@latest
```

```go
package main

import (
    "context"
    "log"

    postalcode "github.com/rallisf1/greek-postal-code-db/go"
)

func main() {
    client, err := postalcode.NewClient()
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()

    postcode, err := client.GetPostcode(context.Background(), "10431", postalcode.PostcodeOptions{
        IncludeHierarchy: true,
        IncludeStreets: true,
    })
    if err != nil {
        log.Fatal(err)
    }
    log.Println(postcode.Hierarchy["municipality"].Name)
}
```

`Client` exposes `ListRegions`, `ListRegionalUnits`, `ListMunicipalities`, `ListMunicipalUnits`, `ListCommunities`, the corresponding `Search…` methods, `GetPostcode`, `ValidateAddress`, and `Close`. All queries accept `context.Context` and are read-only.

The entity option structs support a positive `Limit`, `IncludeHierarchy`, and (except regions) `IncludeOfficialCode`; the child option structs add the relevant optional parent ID. `GetPostcode` accepts `PostcodeOptions`, and `ValidateAddress` returns independent `Valid`, `Invalid`, or `NotEvaluated` component statuses.

## Releases

Because this module lives in the `go/` subdirectory, tag releases as `go/vX.Y.Z` (for example, `go/v0.1.0`).
