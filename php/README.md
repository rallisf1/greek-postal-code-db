# Greek Postal Code DB for PHP

Offline, read-only Greek postal-code data for PHP 8.1+. The package includes the SQLite database and requires PDO SQLite.

```bash
composer require rallisf1/greek-postal-code-db
```

```php
use Rallisf1\GreekPostalCodeDb\PostalCodeClient;

$client = new PostalCodeClient();
$postcode = $client->getPostcode('10431', [
    'include' => ['hierarchy' => true, 'streets' => true],
]);
$municipalities = $client->searchMunicipalities('Αθην', [
    'include' => ['hierarchy' => true],
]);
$client->close();
```

The methods mirror the TypeScript client: `listRegions`, `listRegionalUnits`, `listMunicipalities`, `listMunicipalUnits`, `listCommunities`, all five corresponding `search…` methods, `getPostcode`, `validateAddress`, and `close`.

List/search options use camelCase: `regionId`, `regionalUnitId`, `municipalityId`, `includeOfficialCode`, `limit`, and `include => ['hierarchy' => true]`. `getPostcode` additionally accepts `include => ['streets' => true]`.

`validateAddress` accepts the same keys as the TypeScript client (`postcode`, `street`, `houseNumber`, `municipality`, `municipalUnit`, `community`, `regionalUnit`, and `region`) and reports each supplied component independently with `valid`, `invalid`, or `not_evaluated` status.

## Development

The Composer package manifest and canonical database are at the monorepo root. Run commands from that directory:

```bash
composer test
```
