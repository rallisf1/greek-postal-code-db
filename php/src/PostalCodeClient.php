<?php

declare(strict_types=1);

namespace Rallisf1\GreekPostalCodeDb;

use InvalidArgumentException;
use PDO;
use PDOException;
use RuntimeException;

/**
 * A read-only, offline client for the bundled Greek postal-code database.
 *
 * Results use the same camelCase fields and option names as the TypeScript
 * client. Optional hierarchy and official-code fields are omitted unless
 * requested.
 */
final class PostalCodeClient
{
    private ?PDO $pdo;
    private readonly string $databasePath;

    public function __construct()
    {
        $this->databasePath = dirname(__DIR__, 2) . '/library.sqlite';
        if (!is_file($this->databasePath)) {
            throw new RuntimeException('The bundled library.sqlite asset is missing.');
        }

        $encodedPath = str_replace('%2F', '/', rawurlencode($this->databasePath));
        try {
            $this->pdo = new PDO('sqlite:file:' . $encodedPath . '?mode=ro', null, null, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
            $this->pdo->exec('PRAGMA query_only = ON');
        } catch (PDOException $exception) {
            throw new RuntimeException('Unable to open the bundled SQLite database read-only.', 0, $exception);
        }
    }

    public function close(): void
    {
        $this->pdo = null;
    }

    /** @return list<array{id:int, name:string, hierarchy?:array<string, mixed>}> */
    public function listRegions(array $options = []): array
    {
        return $this->listEntities('regions', null, null, $options, false);
    }

    /** @return list<array<string, mixed>> */
    public function listRegionalUnits(array $options = []): array
    {
        return $this->listEntities('regional_units', 'region_id', $this->parentId($options, 'regionId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function listMunicipalities(array $options = []): array
    {
        return $this->listEntities('municipalities', 'regional_unit_id', $this->parentId($options, 'regionalUnitId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function listMunicipalUnits(array $options = []): array
    {
        return $this->listEntities('municipal_units', 'municipality_id', $this->parentId($options, 'municipalityId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function listCommunities(array $options = []): array
    {
        return $this->listEntities('communities', 'municipality_id', $this->parentId($options, 'municipalityId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function searchRegions(string $query, array $options = []): array
    {
        return $this->searchEntities('regions', null, $query, null, $options, false);
    }

    /** @return list<array<string, mixed>> */
    public function searchRegionalUnits(string $query, array $options = []): array
    {
        return $this->searchEntities('regional_units', 'region_id', $query, $this->parentId($options, 'regionId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function searchMunicipalities(string $query, array $options = []): array
    {
        return $this->searchEntities('municipalities', 'regional_unit_id', $query, $this->parentId($options, 'regionalUnitId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function searchMunicipalUnits(string $query, array $options = []): array
    {
        return $this->searchEntities('municipal_units', 'municipality_id', $query, $this->parentId($options, 'municipalityId'), $options, $this->includeOfficialCode($options));
    }

    /** @return list<array<string, mixed>> */
    public function searchCommunities(string $query, array $options = []): array
    {
        return $this->searchEntities('communities', 'municipality_id', $query, $this->parentId($options, 'municipalityId'), $options, $this->includeOfficialCode($options));
    }

    /** @return array<string, mixed>|null */
    public function getPostcode(string $postcode, array $options = []): ?array
    {
        if (!preg_match('/^\d{5}$/D', $postcode)) {
            return null;
        }
        $row = $this->one('SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?', [$postcode]);
        if ($row === null) {
            return null;
        }
        $result = $this->location($row);
        $include = $options['include'] ?? [];
        if (!is_array($include)) {
            throw new InvalidArgumentException('include must be an array');
        }
        if (($include['hierarchy'] ?? false) === true) {
            $result['hierarchy'] = $this->postcodeHierarchy($result);
        }
        if (($include['streets'] ?? false) === true) {
            $result['streets'] = array_map(fn (array $street): array => $this->street($street), $this->all('SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id', [$postcode]));
        }
        return $result;
    }

    /**
     * @param array{postcode:string, street?:string, houseNumber?:string|int, municipality?:string|int, municipalUnit?:string|int, community?:string|int, regionalUnit?:string|int, region?:string|int} $address
     * @return array<string, array<string, mixed>>
     */
    public function validateAddress(array $address): array
    {
        $postcodeInput = $address['postcode'] ?? null;
        $postcode = is_string($postcodeInput) ? $this->getPostcode($postcodeInput, ['include' => ['hierarchy' => true, 'streets' => array_key_exists('street', $address) || array_key_exists('houseNumber', $address)]]) : null;
        $result = ['postcode' => ['status' => 'invalid', 'input' => $postcodeInput]];
        if (!is_string($postcodeInput) || !preg_match('/^\d{5}$/D', $postcodeInput)) {
            $result['postcode']['reason'] = 'postcode_must_be_exactly_five_digits';
        } elseif ($postcode === null) {
            $result['postcode']['reason'] = 'postcode_not_found';
        } else {
            $result['postcode'] = ['status' => 'valid', 'input' => $postcodeInput, 'matches' => [$postcode]];
        }

        $keys = ['municipality' => 'municipalities', 'municipalUnit' => 'municipal_units', 'community' => 'communities', 'regionalUnit' => 'regional_units', 'region' => 'regions'];
        if ($postcode === null) {
            if (array_key_exists('street', $address)) $result['street'] = $this->notEvaluated($address['street'], 'postcode_not_found');
            if (array_key_exists('houseNumber', $address)) $result['houseNumber'] = $this->notEvaluated($address['houseNumber'], 'postcode_not_found');
            foreach ($keys as $key => $_) if (array_key_exists($key, $address)) $result[$key] = $this->notEvaluated($address[$key], 'postcode_not_found');
            return $result;
        }

        /** @var array<string, mixed> $hierarchy */
        $hierarchy = $postcode['hierarchy'];
        foreach ($keys as $key => $table) {
            if (array_key_exists($key, $address)) $result[$key] = $this->validateReference($table, $address[$key], $hierarchy[$key] ?? null);
        }
        if (array_key_exists('street', $address)) {
            $streetInput = $address['street'];
            $matches = is_string($streetInput) ? array_values(array_filter($postcode['streets'] ?? [], fn (array $street): bool => self::normalizeName($street['name']) === self::normalizeName($streetInput))) : [];
            $result['street'] = ['status' => $matches === [] ? 'invalid' : 'valid', 'input' => $streetInput, 'matches' => $matches];
            if ($matches === []) $result['street']['reason'] = 'street_not_found_for_postcode';
        }
        if (array_key_exists('houseNumber', $address)) {
            $houseNumber = $address['houseNumber'];
            if (!isset($result['street']) || $result['street']['status'] !== 'valid') {
                $result['houseNumber'] = $this->notEvaluated($houseNumber, 'street_is_required_and_must_be_valid');
            } elseif ((!is_int($houseNumber) && !(is_string($houseNumber) && preg_match('/^\d+$/D', $houseNumber))) || (int) $houseNumber <= 0) {
                $result['houseNumber'] = ['status' => 'invalid', 'input' => $houseNumber, 'reason' => 'house_number_must_be_a_positive_integer'];
            } else {
                $checks = array_map(fn (array $street): ?bool => $this->containsHouseNumber($street, (int) $houseNumber), $result['street']['matches']);
                $usable = array_values(array_filter($checks, fn (?bool $check): bool => $check !== null));
                $result['houseNumber'] = ['status' => $usable === [] || in_array(true, $usable, true) ? 'valid' : 'invalid', 'input' => $houseNumber, 'matches' => $result['street']['matches']];
                if ($usable === []) $result['houseNumber']['reason'] = 'street_has_no_usable_range';
            }
        }
        return $result;
    }

    /** @return list<array<string, mixed>> */
    private function listEntities(string $table, ?string $foreignKey, ?int $parentId, array $options, bool $officialCode): array
    {
        $columns = 'id, name' . ($officialCode ? ', official_code' : '');
        $rows = $foreignKey !== null && $parentId !== null
            ? $this->all("SELECT {$columns} FROM {$table} WHERE {$foreignKey} = ? ORDER BY name, id", [$parentId])
            : $this->all("SELECT {$columns} FROM {$table} ORDER BY name, id");
        $hierarchy = ($options['include']['hierarchy'] ?? false) === true;
        $entities = array_map(fn (array $row): array => $this->withHierarchy($table, $this->entity($row, $officialCode), $hierarchy), $rows);
        return $this->limit($entities, $options['limit'] ?? null);
    }

    /** @return list<array<string, mixed>> */
    private function searchEntities(string $table, ?string $foreignKey, string $query, ?int $parentId, array $options, bool $officialCode): array
    {
        $normalized = self::normalizeName($query);
        if ($normalized === '') return [];
        $matches = array_values(array_filter($this->listEntities($table, $foreignKey, $parentId, [], $officialCode), fn (array $entity): bool => str_starts_with(self::normalizeName($entity['name']), $normalized)));
        $hierarchy = ($options['include']['hierarchy'] ?? false) === true;
        $matches = array_map(fn (array $entity): array => $this->withHierarchy($table, $entity, $hierarchy), $matches);
        return $this->limit($matches, $options['limit'] ?? null);
    }

    /** @return array<string, mixed> */
    private function withHierarchy(string $table, array $entity, bool $include): array
    {
        if ($include) $entity['hierarchy'] = $this->entityHierarchy($table, $entity['id']);
        return $entity;
    }

    /** @return array<string, mixed> */
    private function entityHierarchy(string $table, int $id): array
    {
        if ($table === 'regions') {
            $region = $this->one('SELECT decentralized_administration_id FROM regions WHERE id = ?', [$id]);
            return ['decentralizedAdministration' => $region === null ? null : $this->named($this->one('SELECT id, name FROM decentralized_administrations WHERE id = ?', [(int) $region['decentralized_administration_id']]))];
        }
        if ($table === 'regional_units') return $this->regionalUnitHierarchy($id);
        if ($table === 'municipalities') return $this->municipalityHierarchy($id);
        $child = $this->one("SELECT municipality_id FROM {$table} WHERE id = ?", [$id]);
        return $child === null ? ['municipality' => null, 'regionalUnit' => null, 'region' => null, 'decentralizedAdministration' => null] : $this->municipalityChildHierarchy((int) $child['municipality_id']);
    }

    /** @return array<string, mixed> */
    private function postcodeHierarchy(array $location): array
    {
        $municipality = $location['municipalityId'] === null ? null : $this->one('SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?', [$location['municipalityId']]);
        return [
            'municipalUnit' => $location['municipalUnitId'] === null ? null : $this->coded($this->one('SELECT id, name, official_code FROM municipal_units WHERE id = ?', [$location['municipalUnitId']])),
            'community' => $location['communityId'] === null ? null : $this->coded($this->one('SELECT id, name, official_code FROM communities WHERE id = ?', [$location['communityId']])),
            'municipality' => $this->coded($municipality),
            ...($municipality === null ? ['regionalUnit' => null, 'region' => null, 'decentralizedAdministration' => null] : $this->municipalityHierarchy((int) $municipality['id'])),
        ];
    }

    /** @return array<string, mixed> */
    private function regionalUnitHierarchy(int $regionalUnitId): array
    {
        $unit = $this->one('SELECT region_id FROM regional_units WHERE id = ?', [$regionalUnitId]);
        $region = $unit === null ? null : $this->one('SELECT id, name, decentralized_administration_id FROM regions WHERE id = ?', [(int) $unit['region_id']]);
        return ['region' => $this->named($region), 'decentralizedAdministration' => $region === null ? null : $this->named($this->one('SELECT id, name FROM decentralized_administrations WHERE id = ?', [(int) $region['decentralized_administration_id']]))];
    }

    /** @return array<string, mixed> */
    private function municipalityHierarchy(int $municipalityId): array
    {
        $municipality = $this->one('SELECT regional_unit_id FROM municipalities WHERE id = ?', [$municipalityId]);
        $unit = $municipality === null ? null : $this->one('SELECT id, name, region_id, official_code FROM regional_units WHERE id = ?', [(int) $municipality['regional_unit_id']]);
        return ['regionalUnit' => $this->coded($unit), ...($unit === null ? ['region' => null, 'decentralizedAdministration' => null] : $this->regionalUnitHierarchy((int) $unit['id']))];
    }

    /** @return array<string, mixed> */
    private function municipalityChildHierarchy(int $municipalityId): array
    {
        $municipality = $this->one('SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?', [$municipalityId]);
        return ['municipality' => $this->coded($municipality), ...($municipality === null ? ['regionalUnit' => null, 'region' => null, 'decentralizedAdministration' => null] : $this->municipalityHierarchy((int) $municipality['id']))];
    }

    /** @return array<string, mixed> */
    private function validateReference(string $table, mixed $reference, mixed $linked): array
    {
        if (!is_string($reference) && !is_int($reference)) return ['status' => 'invalid', 'input' => $reference, 'matches' => [], 'reason' => 'reference_must_be_a_name_or_id'];
        if (is_string($reference) && self::normalizeName($reference) === '') return ['status' => 'invalid', 'input' => $reference, 'matches' => [], 'reason' => 'reference_must_not_be_empty'];
        $columns = $table === 'regions' ? 'id, name' : 'id, name, official_code';
        $matches = is_int($reference)
            ? array_map(fn (array $row): array => $this->entity($row, $table !== 'regions'), $this->all("SELECT {$columns} FROM {$table} WHERE id = ?", [$reference]))
            : array_values(array_filter(array_map(fn (array $row): array => $this->entity($row, $table !== 'regions'), $this->all("SELECT {$columns} FROM {$table} ORDER BY name, id")), fn (array $candidate): bool => str_starts_with(self::normalizeName($candidate['name']), self::normalizeName($reference))));
        $valid = is_array($linked) && array_filter($matches, fn (array $candidate): bool => $candidate['id'] === $linked['id']) !== [];
        $result = ['status' => $valid ? 'valid' : 'invalid', 'input' => $reference, 'matches' => $matches];
        if ($linked === null) $result['reason'] = 'postcode_has_no_linked_entity';
        return $result;
    }

    /** @return array<string, mixed> */
    private function entity(array $row, bool $officialCode): array
    {
        $entity = ['id' => (int) $row['id'], 'name' => (string) $row['name']];
        if ($officialCode) $entity['officialCode'] = $row['official_code'] === null ? null : (string) $row['official_code'];
        return $entity;
    }

    private function named(?array $row): ?array { return $row === null ? null : $this->entity($row, false); }
    private function coded(?array $row): ?array { return $row === null ? null : $this->entity($row, true); }
    private function street(array $row): array { return ['id' => (int) $row['id'], 'postcode' => (string) $row['postcode'], 'name' => (string) $row['name'], 'oddStart' => $row['odd_start'], 'oddEnd' => $row['odd_end'], 'evenStart' => $row['even_start'], 'evenEnd' => $row['even_end']]; }
    private function location(array $row): array { return ['postcode' => (string) $row['postcode'], 'latitude' => $row['latitude'] === null ? null : (float) $row['latitude'], 'longitude' => $row['longitude'] === null ? null : (float) $row['longitude'], 'localArea' => $row['local_area'], 'municipalUnitId' => $row['municipal_unit_id'] === null ? null : (int) $row['municipal_unit_id'], 'communityId' => $row['community_id'] === null ? null : (int) $row['community_id'], 'municipalityId' => $row['municipality_id'] === null ? null : (int) $row['municipality_id']]; }
    private function notEvaluated(mixed $input, string $reason): array { return ['status' => 'not_evaluated', 'input' => $input, 'reason' => $reason]; }

    private function containsHouseNumber(array $street, int $number): ?bool
    {
        $odd = $number % 2 === 1;
        $start = $this->rangeNumber($street[$odd ? 'oddStart' : 'evenStart']);
        $endText = $street[$odd ? 'oddEnd' : 'evenEnd'];
        $end = $this->rangeNumber($endText);
        if ($start === null || ($end === null && self::normalizeName((string) $endText) !== 'τελ')) return null;
        return $number >= $start && (self::normalizeName((string) $endText) === 'τελ' || $number <= $end);
    }

    private function rangeNumber(?string $value): ?int { return $value !== null && preg_match('/^\s*(\d+)/u', $value, $matches) ? (int) $matches[1] : null; }
    private function includeOfficialCode(array $options): bool { return ($options['includeOfficialCode'] ?? false) === true; }
    private function parentId(array $options, string $key): ?int { if (!array_key_exists($key, $options)) return null; if (!is_int($options[$key]) || $options[$key] <= 0) throw new InvalidArgumentException("{$key} must be a positive integer"); return $options[$key]; }
    private function limit(array $rows, mixed $limit): array { if ($limit === null) return $rows; if (!is_int($limit) || $limit <= 0) throw new InvalidArgumentException('limit must be a positive integer'); return array_slice($rows, 0, $limit); }
    /** @return list<array<string, mixed>> */
    private function all(string $sql, array $parameters = []): array { $statement = $this->pdo()->prepare($sql); $statement->execute($parameters); return $statement->fetchAll(); }
    /** @return array<string, mixed>|null */
    private function one(string $sql, array $parameters = []): ?array { $statement = $this->pdo()->prepare($sql); $statement->execute($parameters); $row = $statement->fetch(); return $row === false ? null : $row; }
    private function pdo(): PDO { if ($this->pdo === null) throw new RuntimeException('PostalCodeClient is closed'); return $this->pdo; }

    private static function normalizeName(string $value): string
    {
        $value = mb_strtolower($value, 'UTF-8');
        $value = strtr($value, ['ά' => 'α', 'έ' => 'ε', 'ή' => 'η', 'ί' => 'ι', 'ό' => 'ο', 'ύ' => 'υ', 'ώ' => 'ω', 'ϊ' => 'ι', 'ϋ' => 'υ', 'ΐ' => 'ι', 'ΰ' => 'υ', 'ς' => 'σ']);
        return preg_replace('/[^\p{L}\p{N}]+/u', '', $value) ?? '';
    }
}
