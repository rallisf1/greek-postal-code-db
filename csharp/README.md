# Greek Postal Code DB for .NET

Offline, read-only Greek postal-code data backed by the SQLite database embedded in this package. It targets .NET 10 or later and has no write API.

This is a package inside the [Greek Postal Code DB monorepo](https://github.com/rallisf1/greek-postal-code-db). Install it from NuGet:

```sh
dotnet add package GreekPostalCodeDb
```

```csharp
using GreekPostalCodeDb;

using var client = PostalCodeClient.Create();

var municipalities = client.SearchMunicipalities("Αθην", new(IncludeHierarchy: true));
var postcode = client.GetPostcode("10431", new(IncludeHierarchy: true, IncludeStreets: true));
var validation = client.ValidateAddress(new(
    Postcode: "10431",
    Street: "Βενιζέλου Ελευθερίου",
    HouseNumber: 69,
    Municipality: LocalityReference.ByName("Αθην")));
```

The entity list and search methods are `ListRegions`, `ListRegionalUnits`, `ListMunicipalities`, `ListMunicipalUnits`, `ListCommunities`, and their `Search…` equivalents. All support a positive `Limit`; child entities accept their corresponding parent-ID option; `IncludeHierarchy` adds their ancestors. Entities with source codes support `IncludeOfficialCode`.

`GetPostcode` requires exactly five digits and returns `null` when unknown. `PostcodeOptions` can request hierarchy and streets. `ValidateAddress` reports independent `Valid`, `Invalid`, or `NotEvaluated` results for every supplied component—there is intentionally no aggregate validity flag.
