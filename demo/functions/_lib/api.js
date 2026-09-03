const cacheHeaders = { 'cache-control': 'public, max-age=300' };

export function normalizeName(value) {
  return String(value).normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase('el').replace(/[^\p{L}\p{N}]+/gu, '');
}

function json(value, init = {}) {
  return Response.json(value, { ...init, headers: { ...cacheHeaders, ...(init.headers ?? {}) } });
}
function badRequest(message) { return json({ error: message }, { status: 400, headers: { 'cache-control': 'no-store' } }); }
function parseId(value) { return /^\d+$/u.test(value ?? '') && Number(value) > 0 ? Number(value) : null; }
function parseLimit(value) {
  if (value === null) return 20;
  const limit = Number(value);
  return Number.isInteger(limit) && limit > 0 && limit <= 50 ? limit : null;
}
async function all(db, sql, values = []) { return (await db.prepare(sql).bind(...values).all()).results; }
async function first(db, sql, values = []) { return db.prepare(sql).bind(...values).first(); }
function entity(row, coded = false) {
  if (!row) return null;
  return coded ? { id: row.id, name: row.name, officialCode: row.official_code ?? null } : { id: row.id, name: row.name };
}
function street(row) {
  return { id: row.id, postcode: row.postcode, name: row.name, oddStart: row.odd_start, oddEnd: row.odd_end, evenStart: row.even_start, evenEnd: row.even_end };
}

async function postcode(db, value, includeStreets = true) {
  if (!/^\d{5}$/u.test(value)) return null;
  const row = await first(db, `SELECT l.postcode,l.latitude,l.longitude,l.local_area,l.municipal_unit_id,l.community_id,l.municipality_id,
    mu.id mu_id,mu.name mu_name,mu.official_code mu_code,c.id c_id,c.name c_name,c.official_code c_code,
    m.id m_id,m.name m_name,m.official_code m_code,ru.id ru_id,ru.name ru_name,ru.official_code ru_code,
    r.id r_id,r.name r_name,da.id da_id,da.name da_name
    FROM locations l LEFT JOIN municipal_units mu ON mu.id=l.municipal_unit_id LEFT JOIN communities c ON c.id=l.community_id
    JOIN municipalities m ON m.id=l.municipality_id JOIN regional_units ru ON ru.id=m.regional_unit_id
    JOIN regions r ON r.id=ru.region_id LEFT JOIN decentralized_administrations da ON da.id=r.decentralized_administration_id
    WHERE l.postcode = ?`, [value]);
  if (!row) return null;
  const result = {
    postcode: row.postcode, latitude: row.latitude, longitude: row.longitude, localArea: row.local_area,
    municipalUnitId: row.municipal_unit_id, communityId: row.community_id, municipalityId: row.municipality_id,
    hierarchy: {
      municipalUnit: row.mu_id ? { id: row.mu_id, name: row.mu_name, officialCode: row.mu_code } : null,
      community: row.c_id ? { id: row.c_id, name: row.c_name, officialCode: row.c_code } : null,
      municipality: { id: row.m_id, name: row.m_name, officialCode: row.m_code },
      regionalUnit: { id: row.ru_id, name: row.ru_name, officialCode: row.ru_code },
      region: { id: row.r_id, name: row.r_name },
      decentralizedAdministration: row.da_id ? { id: row.da_id, name: row.da_name } : null
    }
  };
  if (includeStreets) result.streets = (await all(db, 'SELECT id,postcode,name,odd_start,odd_end,even_start,even_end FROM streets WHERE postcode = ? ORDER BY name,id', [value])).map(street);
  return result;
}

function rangeNumber(value) { const match = /^\s*(\d+)/u.exec(value ?? ''); return match ? Number(match[1]) : null; }
function containsHouseNumber(row, number) {
  const odd = number % 2 === 1, start = rangeNumber(odd ? row.oddStart : row.evenStart), endText = odd ? row.oddEnd : row.evenEnd, end = rangeNumber(endText);
  if (start === null || (end === null && normalizeName(endText ?? '') !== 'τελ')) return null;
  return number >= start && (normalizeName(endText ?? '') === 'τελ' || number <= end);
}
function notEvaluated(input, reason) { return { status: 'not_evaluated', input, reason }; }

async function validateReference(db, table, coded, reference, linked) {
  if (typeof reference === 'string' && !normalizeName(reference)) return { status: 'invalid', input: reference, matches: [], reason: 'reference_must_not_be_empty' };
  const rows = typeof reference === 'number'
    ? await all(db, `SELECT id,name${coded ? ',official_code' : ''} FROM ${table} WHERE id = ?`, [reference])
    : (await all(db, `SELECT id,name${coded ? ',official_code' : ''} FROM ${table} ORDER BY name,id`)).filter((row) => normalizeName(row.name).startsWith(normalizeName(reference)));
  const matches = rows.map((row) => entity(row, coded));
  return { status: linked && matches.some((candidate) => candidate.id === linked.id) ? 'valid' : 'invalid', input: reference, matches, reason: linked ? undefined : 'postcode_has_no_linked_entity' };
}

async function validateAddress(db, address) {
  if (!address || typeof address.postcode !== 'string') return null;
  const result = { postcode: { status: 'invalid', input: address.postcode } };
  const resolved = await postcode(db, address.postcode, address.street !== undefined || address.houseNumber !== undefined);
  if (!/^\d{5}$/u.test(address.postcode)) result.postcode.reason = 'postcode_must_be_exactly_five_digits';
  else if (!resolved) result.postcode.reason = 'postcode_not_found';
  else result.postcode = { status: 'valid', input: address.postcode, matches: [resolved] };
  const fields = [['municipality', 'municipalities', true, 'municipality'], ['municipalUnit', 'municipal_units', true, 'municipalUnit'], ['community', 'communities', true, 'community'], ['regionalUnit', 'regional_units', true, 'regionalUnit'], ['region', 'regions', false, 'region']];
  if (!resolved) {
    for (const [name] of fields) if (address[name] !== undefined) result[name] = notEvaluated(address[name], 'postcode_not_found');
    if (address.street !== undefined) result.street = notEvaluated(address.street, 'postcode_not_found');
    if (address.houseNumber !== undefined) result.houseNumber = notEvaluated(address.houseNumber, 'postcode_not_found');
    return result;
  }
  for (const [name, table, coded, hierarchyName] of fields) if (address[name] !== undefined) result[name] = await validateReference(db, table, coded, address[name], resolved.hierarchy[hierarchyName]);
  if (address.street !== undefined) {
    const matches = resolved.streets.filter((candidate) => normalizeName(candidate.name) === normalizeName(address.street));
    result.street = { status: matches.length ? 'valid' : 'invalid', input: address.street, matches, reason: matches.length ? undefined : 'street_not_found_for_postcode' };
  }
  if (address.houseNumber !== undefined) {
    if (!result.street || result.street.status !== 'valid') result.houseNumber = notEvaluated(address.houseNumber, 'street_is_required_and_must_be_valid');
    else {
      const number = typeof address.houseNumber === 'number' ? address.houseNumber : /^\d+$/u.test(String(address.houseNumber)) ? Number(address.houseNumber) : NaN;
      if (!Number.isInteger(number) || number <= 0) result.houseNumber = { status: 'invalid', input: address.houseNumber, reason: 'house_number_must_be_a_positive_integer' };
      else {
        const checks = result.street.matches.map((candidate) => containsHouseNumber(candidate, number)).filter((value) => value !== null);
        result.houseNumber = { status: checks.length === 0 || checks.some(Boolean) ? 'valid' : 'invalid', input: address.houseNumber, matches: result.street.matches, reason: checks.length ? undefined : 'street_has_no_usable_range' };
      }
    }
  }
  return result;
}

export async function handleApi(request, db) {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  if (method === 'GET' && path === '/api/regions') return json((await all(db, 'SELECT id,name FROM regions ORDER BY name,id')).map((row) => entity(row)));
  if (method === 'GET' && path === '/api/regional-units') {
    const regionId = parseId(url.searchParams.get('regionId'));
    if (!regionId) return badRequest('regionId must be a positive integer');
    return json((await all(db, 'SELECT id,name,official_code FROM regional_units WHERE region_id = ? ORDER BY name,id', [regionId])).map((row) => entity(row, true)));
  }
  if (method === 'GET' && path === '/api/municipalities/search') {
    const query = normalizeName(url.searchParams.get('q') ?? ''), limit = parseLimit(url.searchParams.get('limit'));
    if (!query) return badRequest('q is required');
    if (limit === null) return badRequest('limit must be an integer from 1 to 50');
    const rows = await all(db, 'SELECT id,name,official_code FROM municipalities ORDER BY name,id');
    return json(rows.filter((row) => normalizeName(row.name).startsWith(query)).slice(0, limit).map((row) => entity(row, true)));
  }
  if (method === 'GET' && /^\/api\/postcodes\/\d{5}$/u.test(path)) {
    const result = await postcode(db, path.slice('/api/postcodes/'.length));
    return result ? json(result) : json({ error: 'postcode_not_found' }, { status: 404 });
  }
  if (method === 'POST' && path === '/api/validate-address') {
    let body;
    try { body = await request.json(); } catch { return badRequest('body must be JSON'); }
    const result = await validateAddress(db, body);
    return result ? json(result, { headers: { 'cache-control': 'no-store' } }) : badRequest('postcode is required');
  }
  return json({ error: 'not_found' }, { status: 404 });
}
