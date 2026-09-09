# Greek Postal Code DB for Java

An offline, read-only Java 21+ client for Greek postal-code data. The SQLite snapshot is embedded in the JAR, so no database path or write API is exposed.

This package belongs to the [Greek Postal Code DB monorepo](https://github.com/rallisf1/greek-postal-code-db). Once published to Maven Central, add it to Maven:

```xml
<dependency>
  <groupId>io.github.rallisf1</groupId>
  <artifactId>greek-postal-code-db</artifactId>
  <version>0.1.0</version>
</dependency>
```

```java
import io.github.rallisf1.greekpostalcode.Models.*;
import io.github.rallisf1.greekpostalcode.PostalCodeClient;

try (var client = PostalCodeClient.create()) {
    var municipalities = client.searchMunicipalities("Αθην", new MunicipalityOptions(null, null, true, false));
    var postcode = client.getPostcode("10431", new PostcodeOptions(true, true));
    var validation = client.validateAddress(new AddressInput(
        "10431", "Βενιζέλου Ελευθερίου", 69,
        LocalityReference.byName("Αθην"), null, null, null, null));
}
```

The five list/search entity groups support parent IDs, normalized Greek name-prefix matching, positive limits, official codes, and optional hierarchy. `getPostcode` returns `null` for an unknown or malformed postcode. `validateAddress` returns independent `VALID`, `INVALID`, or `NOT_EVALUATED` results for each supplied component; it deliberately has no aggregate validity flag.
