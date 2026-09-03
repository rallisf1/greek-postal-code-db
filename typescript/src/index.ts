import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

type SqlValue = string | number | null;
type SqlRow = Record<string, unknown>;

interface Statement {
  all(...parameters: SqlValue[]): SqlRow[];
  get(...parameters: SqlValue[]): SqlRow | undefined;
}

interface ReadonlyDatabase {
  prepare(sql: string): Statement;
  close(): void;
}

export interface NamedEntity {
  id: number;
  name: string;
}

export interface CodedEntity extends NamedEntity {
  /** Present only when the caller requested `includeOfficialCode`. */
  officialCode?: string | null;
}

export interface DecentralizedAdministration extends NamedEntity {}

export interface RegionHierarchy {
  decentralizedAdministration: DecentralizedAdministration | null;
}

export interface RegionalUnitHierarchy extends RegionHierarchy {
  region: Region | null;
}

export interface MunicipalityHierarchy extends RegionalUnitHierarchy {
  regionalUnit: RegionalUnit | null;
}

export interface MunicipalityChildHierarchy extends MunicipalityHierarchy {
  municipality: Municipality | null;
}

export interface Region extends NamedEntity {
  hierarchy?: RegionHierarchy;
}

export interface RegionalUnit extends CodedEntity {
  hierarchy?: RegionalUnitHierarchy;
}

export interface Municipality extends CodedEntity {
  hierarchy?: MunicipalityHierarchy;
}

export interface MunicipalUnit extends CodedEntity {
  hierarchy?: MunicipalityChildHierarchy;
}

export interface Community extends CodedEntity {
  hierarchy?: MunicipalityChildHierarchy;
}

export interface Street {
  id: number;
  postcode: string;
  name: string;
  oddStart: string | null;
  oddEnd: string | null;
  evenStart: string | null;
  evenEnd: string | null;
}

export interface PostcodeLocation {
  postcode: string;
  latitude: number | null;
  longitude: number | null;
  localArea: string | null;
  municipalUnitId: number | null;
  communityId: number | null;
  municipalityId: number | null;
}

export interface PostcodeHierarchy {
  municipalUnit: MunicipalUnit | null;
  community: Community | null;
  municipality: Municipality | null;
  regionalUnit: RegionalUnit | null;
  region: Region | null;
  decentralizedAdministration: DecentralizedAdministration | null;
}

export interface PostcodeResult extends PostcodeLocation {
  hierarchy?: PostcodeHierarchy;
  streets?: Street[];
}

export interface ListOptions {
  limit?: number;
  include?: {
    hierarchy?: boolean;
  };
}

export interface CodedListOptions extends ListOptions {
  includeOfficialCode?: boolean;
}

export interface RegionalUnitOptions extends CodedListOptions {
  regionId?: number;
}

export interface MunicipalityOptions extends CodedListOptions {
  regionalUnitId?: number;
}

export interface MunicipalityChildOptions extends CodedListOptions {
  municipalityId?: number;
}

export interface PostcodeLookupOptions {
  include?: {
    hierarchy?: boolean;
    streets?: boolean;
  };
}

export type EntityReference = string | number;

export interface AddressInput {
  postcode: string;
  street?: string;
  houseNumber?: string | number;
  municipality?: EntityReference;
  municipalUnit?: EntityReference;
  community?: EntityReference;
  regionalUnit?: EntityReference;
  region?: EntityReference;
}

export type ValidationStatus = 'valid' | 'invalid' | 'not_evaluated';

export interface ValidationResult<T> {
  status: ValidationStatus;
  input: unknown;
  matches?: T[];
  reason?: string;
}

export interface AddressValidation {
  postcode: ValidationResult<PostcodeLocation>;
  street?: ValidationResult<Street>;
  houseNumber?: ValidationResult<Street>;
  municipality?: ValidationResult<Municipality>;
  municipalUnit?: ValidationResult<MunicipalUnit>;
  community?: ValidationResult<Community>;
  regionalUnit?: ValidationResult<RegionalUnit>;
  region?: ValidationResult<Region>;
}

export interface PostalCodeClient {
  close(): void;
  listRegions(options?: ListOptions): Region[];
  listRegionalUnits(options?: RegionalUnitOptions): RegionalUnit[];
  listMunicipalities(options?: MunicipalityOptions): Municipality[];
  listMunicipalUnits(options?: MunicipalityChildOptions): MunicipalUnit[];
  listCommunities(options?: MunicipalityChildOptions): Community[];
  searchRegions(query: string, options?: ListOptions): Region[];
  searchRegionalUnits(query: string, options?: RegionalUnitOptions): RegionalUnit[];
  searchMunicipalities(query: string, options?: MunicipalityOptions): Municipality[];
  searchMunicipalUnits(query: string, options?: MunicipalityChildOptions): MunicipalUnit[];
  searchCommunities(query: string, options?: MunicipalityChildOptions): Community[];
  getPostcode(postcode: string, options?: PostcodeLookupOptions): PostcodeResult | null;
  validateAddress(address: AddressInput): AddressValidation;
}

const require = createRequire(import.meta.url);
const databasePath = resolve(fileURLToPath(new URL('../data/library.sqlite', import.meta.url)));

function openDatabase(): ReadonlyDatabase {
  if (typeof process !== 'undefined' && process.versions.bun) {
    const { Database } = require('bun:sqlite') as { Database: new (path: string, options: { readonly: boolean }) => ReadonlyDatabase };
    return new Database(databasePath, { readonly: true });
  }
  const { DatabaseSync } = require('node:sqlite') as { DatabaseSync: new (path: string, options: { readOnly: boolean }) => ReadonlyDatabase };
  return new DatabaseSync(databasePath, { readOnly: true });
}

function normalizeName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLocaleLowerCase('el')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

function limitRows<T>(rows: T[], limit: number | undefined): T[] {
  if (limit === undefined) return rows;
  if (!Number.isInteger(limit) || limit <= 0) throw new RangeError('limit must be a positive integer');
  return rows.slice(0, limit);
}

function entity(row: SqlRow, includeOfficialCode: boolean): NamedEntity | CodedEntity {
  const base: NamedEntity = { id: Number(row.id), name: String(row.name) };
  return includeOfficialCode ? { ...base, officialCode: row.official_code === null || row.official_code === undefined ? null : String(row.official_code) } : base;
}

function codedEntity(row: SqlRow): CodedEntity {
  return entity(row, true) as CodedEntity;
}

function street(row: SqlRow): Street {
  return {
    id: Number(row.id), postcode: String(row.postcode), name: String(row.name),
    oddStart: nullableString(row.odd_start), oddEnd: nullableString(row.odd_end),
    evenStart: nullableString(row.even_start), evenEnd: nullableString(row.even_end)
  };
}

function location(row: SqlRow): PostcodeLocation {
  return {
    postcode: String(row.postcode), latitude: nullableNumber(row.latitude), longitude: nullableNumber(row.longitude), localArea: nullableString(row.local_area),
    municipalUnitId: nullableNumber(row.municipal_unit_id), communityId: nullableNumber(row.community_id), municipalityId: nullableNumber(row.municipality_id)
  };
}

function nullableString(value: unknown): string | null { return value === null || value === undefined ? null : String(value); }
function nullableNumber(value: unknown): number | null { return value === null || value === undefined ? null : Number(value); }
function isPostcode(value: string): boolean { return /^\d{5}$/.test(value); }

function rangeNumber(value: string | null): number | null {
  if (value === null) return null;
  const match = /^\s*(\d+)/u.exec(value);
  return match ? Number(match[1]) : null;
}

function containsHouseNumber(row: Street, value: number): boolean | null {
  const isOdd = value % 2 === 1;
  const start = rangeNumber(isOdd ? row.oddStart : row.evenStart);
  const endText = isOdd ? row.oddEnd : row.evenEnd;
  const end = rangeNumber(endText);
  if (start === null || (end === null && normalizeName(endText ?? '') !== 'τελ')) return null;
  return value >= start && (normalizeName(endText ?? '') === 'τελ' || value <= (end as number));
}

export function createPostalCodeClient(): PostalCodeClient {
  const db = openDatabase();
  let closed = false;
  const ensureOpen = () => { if (closed) throw new Error('PostalCodeClient is closed'); };
  const all = (sql: string, ...parameters: SqlValue[]) => { ensureOpen(); return db.prepare(sql).all(...parameters); };
  const get = (sql: string, ...parameters: SqlValue[]) => { ensureOpen(); return db.prepare(sql).get(...parameters); };

  function withHierarchy<T extends NamedEntity>(table: string, item: T, includeHierarchy: boolean): T {
    return includeHierarchy ? { ...item, hierarchy: getEntityHierarchy(table, item.id) } as T : item;
  }

  function listEntities(table: string, foreignKey: string | null, parentId: number | undefined, options: ListOptions, includeOfficialCode: boolean): (NamedEntity | CodedEntity)[] {
    const sql = foreignKey && parentId !== undefined
      ? `SELECT id, name${includeOfficialCode ? ', official_code' : ''} FROM ${table} WHERE ${foreignKey} = ? ORDER BY name, id`
      : `SELECT id, name${includeOfficialCode ? ', official_code' : ''} FROM ${table} ORDER BY name, id`;
    const rows = foreignKey && parentId !== undefined ? all(sql, parentId) : all(sql);
    return limitRows(rows.map((row) => withHierarchy(table, entity(row, includeOfficialCode), options.include?.hierarchy === true)), options.limit);
  }

  function searchEntities(table: string, foreignKey: string | null, query: string, parentId: number | undefined, options: ListOptions, includeOfficialCode: boolean): (NamedEntity | CodedEntity)[] {
    const normalizedQuery = normalizeName(query);
    if (!normalizedQuery) return [];
    return listEntities(table, foreignKey, parentId, {}, includeOfficialCode)
      .filter((item) => normalizeName(item.name).startsWith(normalizedQuery))
      .slice(0, options.limit === undefined ? undefined : checkedLimit(options.limit))
      .map((item) => withHierarchy(table, item, options.include?.hierarchy === true));
  }

  function checkedLimit(limit: number): number {
    if (!Number.isInteger(limit) || limit <= 0) throw new RangeError('limit must be a positive integer');
    return limit;
  }

  function regionalUnitHierarchy(regionalUnitId: number): RegionalUnitHierarchy {
    const regionalUnit = get('SELECT id, name, region_id, official_code FROM regional_units WHERE id = ?', regionalUnitId);
    const region = regionalUnit ? get('SELECT id, name, decentralized_administration_id FROM regions WHERE id = ?', Number(regionalUnit.region_id)) : undefined;
    const decentralizedAdministration = region ? get('SELECT id, name FROM decentralized_administrations WHERE id = ?', Number(region.decentralized_administration_id)) : undefined;
    return {
      region: region ? entity(region, false) as Region : null,
      decentralizedAdministration: decentralizedAdministration ? entity(decentralizedAdministration, false) as DecentralizedAdministration : null
    };
  }

  function municipalityHierarchy(municipalityId: number): MunicipalityHierarchy {
    const municipality = get('SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?', municipalityId);
    if (!municipality) return { regionalUnit: null, region: null, decentralizedAdministration: null };
    const regionalUnit = get('SELECT id, name, region_id, official_code FROM regional_units WHERE id = ?', Number(municipality.regional_unit_id));
    const ancestors = regionalUnit ? regionalUnitHierarchy(Number(regionalUnit.id)) : { region: null, decentralizedAdministration: null };
    return { regionalUnit: regionalUnit ? codedEntity(regionalUnit) as RegionalUnit : null, ...ancestors };
  }

  function municipalityChildHierarchy(municipalityId: number): MunicipalityChildHierarchy {
    const municipality = get('SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?', municipalityId);
    const ancestors = municipality ? municipalityHierarchy(Number(municipality.id)) : { regionalUnit: null, region: null, decentralizedAdministration: null };
    return { municipality: municipality ? codedEntity(municipality) as Municipality : null, ...ancestors };
  }

  function getEntityHierarchy(table: string, id: number): RegionHierarchy | RegionalUnitHierarchy | MunicipalityHierarchy | MunicipalityChildHierarchy {
    if (table === 'regions') {
      const region = get('SELECT decentralized_administration_id FROM regions WHERE id = ?', id);
      const decentralizedAdministration = region ? get('SELECT id, name FROM decentralized_administrations WHERE id = ?', Number(region.decentralized_administration_id)) : undefined;
      return { decentralizedAdministration: decentralizedAdministration ? entity(decentralizedAdministration, false) as DecentralizedAdministration : null };
    }
    if (table === 'regional_units') return regionalUnitHierarchy(id);
    if (table === 'municipalities') return municipalityHierarchy(id);
    const child = get(`SELECT municipality_id FROM ${table} WHERE id = ?`, id);
    return child ? municipalityChildHierarchy(Number(child.municipality_id)) : { municipality: null, regionalUnit: null, region: null, decentralizedAdministration: null };
  }

  function getHierarchy(current: PostcodeLocation): PostcodeHierarchy {
    const municipalUnit = current.municipalUnitId === null ? null : get('SELECT id, name, official_code FROM municipal_units WHERE id = ?', current.municipalUnitId);
    const community = current.communityId === null ? null : get('SELECT id, name, official_code FROM communities WHERE id = ?', current.communityId);
    const municipality = current.municipalityId === null ? null : get('SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?', current.municipalityId);
    const ancestors = municipality ? municipalityHierarchy(Number(municipality.id)) : { regionalUnit: null, region: null, decentralizedAdministration: null };
    return {
      municipalUnit: municipalUnit ? codedEntity(municipalUnit) : null, community: community ? codedEntity(community) : null,
      municipality: municipality ? codedEntity(municipality) : null, ...ancestors
    };
  }

  function getPostcode(postcode: string, options: PostcodeLookupOptions = {}): PostcodeResult | null {
    if (!isPostcode(postcode)) return null;
    const row = get('SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?', postcode);
    if (!row) return null;
    const result: PostcodeResult = location(row);
    if (options.include?.hierarchy) result.hierarchy = getHierarchy(result);
    if (options.include?.streets) result.streets = all('SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id', postcode).map(street);
    return result;
  }

  function validateReference<T extends NamedEntity>(table: string, reference: EntityReference, linked: T | null): ValidationResult<T> {
    if (typeof reference === 'string' && !normalizeName(reference)) {
      return { status: 'invalid', input: reference, matches: [], reason: 'reference_must_not_be_empty' };
    }
    const matches = typeof reference === 'number'
      ? all(`SELECT id, name${table === 'regions' ? '' : ', official_code'} FROM ${table} WHERE id = ?`, reference).map((row) => entity(row, table !== 'regions') as T)
      : all(`SELECT id, name${table === 'regions' ? '' : ', official_code'} FROM ${table} ORDER BY name, id`).map((row) => entity(row, table !== 'regions') as T).filter((candidate) => normalizeName(candidate.name).startsWith(normalizeName(reference)));
    return { status: linked !== null && matches.some((candidate) => candidate.id === linked.id) ? 'valid' : 'invalid', input: reference, matches, reason: linked === null ? 'postcode_has_no_linked_entity' : undefined };
  }

  function notEvaluated<T>(input: unknown, reason: string): ValidationResult<T> { return { status: 'not_evaluated', input, reason }; }

  function validateAddress(address: AddressInput): AddressValidation {
    const result: AddressValidation = { postcode: { status: 'invalid', input: address.postcode } };
    const postcode = getPostcode(address.postcode, { include: { hierarchy: true, streets: address.street !== undefined || address.houseNumber !== undefined } });
    if (!isPostcode(address.postcode)) result.postcode.reason = 'postcode_must_be_exactly_five_digits';
    else if (!postcode) result.postcode.reason = 'postcode_not_found';
    else result.postcode = { status: 'valid', input: address.postcode, matches: [postcode] };

    if (!postcode) {
      if (address.street !== undefined) result.street = notEvaluated(address.street, 'postcode_not_found');
      if (address.houseNumber !== undefined) result.houseNumber = notEvaluated(address.houseNumber, 'postcode_not_found');
      for (const key of ['municipality', 'municipalUnit', 'community', 'regionalUnit', 'region'] as const) if (address[key] !== undefined) result[key] = notEvaluated(address[key], 'postcode_not_found') as never;
      return result;
    }

    const hierarchy = postcode.hierarchy as PostcodeHierarchy;
    if (address.municipality !== undefined) result.municipality = validateReference<Municipality>('municipalities', address.municipality, hierarchy.municipality);
    if (address.municipalUnit !== undefined) result.municipalUnit = validateReference<MunicipalUnit>('municipal_units', address.municipalUnit, hierarchy.municipalUnit);
    if (address.community !== undefined) result.community = validateReference<Community>('communities', address.community, hierarchy.community);
    if (address.regionalUnit !== undefined) result.regionalUnit = validateReference<RegionalUnit>('regional_units', address.regionalUnit, hierarchy.regionalUnit);
    if (address.region !== undefined) result.region = validateReference<Region>('regions', address.region, hierarchy.region);

    if (address.street !== undefined) {
      const streetInput = address.street;
      const matches = (postcode.streets ?? []).filter((candidate) => normalizeName(candidate.name) === normalizeName(streetInput));
      result.street = { status: matches.length ? 'valid' : 'invalid', input: streetInput, matches, reason: matches.length ? undefined : 'street_not_found_for_postcode' };
    }
    if (address.houseNumber !== undefined) {
      if (!result.street || result.street.status !== 'valid') result.houseNumber = notEvaluated(address.houseNumber, 'street_is_required_and_must_be_valid');
      else {
        const number = typeof address.houseNumber === 'number' ? address.houseNumber : /^\d+$/u.test(address.houseNumber) ? Number(address.houseNumber) : NaN;
        if (!Number.isInteger(number) || number <= 0) result.houseNumber = { status: 'invalid', input: address.houseNumber, reason: 'house_number_must_be_a_positive_integer' };
        else {
          const checks = result.street.matches!.map((candidate) => containsHouseNumber(candidate, number));
          const usableChecks = checks.filter((check): check is boolean => check !== null);
          result.houseNumber = {
            status: usableChecks.length === 0 || usableChecks.some(Boolean) ? 'valid' : 'invalid', input: address.houseNumber,
            matches: result.street.matches, reason: usableChecks.length === 0 ? 'street_has_no_usable_range' : undefined
          };
        }
      }
    }
    return result;
  }

  return {
    close() { if (!closed) { db.close(); closed = true; } },
    listRegions: (options = {}) => listEntities('regions', null, undefined, options, false) as Region[],
    listRegionalUnits: (options = {}) => listEntities('regional_units', 'region_id', options.regionId, options, options.includeOfficialCode === true) as RegionalUnit[],
    listMunicipalities: (options = {}) => listEntities('municipalities', 'regional_unit_id', options.regionalUnitId, options, options.includeOfficialCode === true) as Municipality[],
    listMunicipalUnits: (options = {}) => listEntities('municipal_units', 'municipality_id', options.municipalityId, options, options.includeOfficialCode === true) as MunicipalUnit[],
    listCommunities: (options = {}) => listEntities('communities', 'municipality_id', options.municipalityId, options, options.includeOfficialCode === true) as Community[],
    searchRegions: (query, options = {}) => searchEntities('regions', null, query, undefined, options, false) as Region[],
    searchRegionalUnits: (query, options = {}) => searchEntities('regional_units', 'region_id', query, options.regionId, options, options.includeOfficialCode === true) as RegionalUnit[],
    searchMunicipalities: (query, options = {}) => searchEntities('municipalities', 'regional_unit_id', query, options.regionalUnitId, options, options.includeOfficialCode === true) as Municipality[],
    searchMunicipalUnits: (query, options = {}) => searchEntities('municipal_units', 'municipality_id', query, options.municipalityId, options, options.includeOfficialCode === true) as MunicipalUnit[],
    searchCommunities: (query, options = {}) => searchEntities('communities', 'municipality_id', query, options.municipalityId, options, options.includeOfficialCode === true) as Community[],
    getPostcode,
    validateAddress
  };
}
