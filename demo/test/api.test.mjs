import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { handleApi, normalizeName } from '../functions/_lib/api.js';

class NodeStatement {
  constructor(statement) { this.statement = statement; this.values = []; }
  bind(...values) { this.values = values; return this; }
  async all() { return { results: this.statement.all(...this.values) }; }
  async first() { return this.statement.get(...this.values) ?? null; }
}
class NodeD1 {
  constructor(path) { this.database = new DatabaseSync(path, { readOnly: true }); }
  prepare(sql) { return new NodeStatement(this.database.prepare(sql)); }
  close() { this.database.close(); }
}

const db = new NodeD1(new URL('../../library.sqlite', import.meta.url).pathname);
test.after(() => db.close());
async function api(path, options) { return handleApi(new Request(`https://demo.invalid${path}`, options), db); }

test('normalizes Greek names and serves lookup endpoints', async () => {
  assert.equal(normalizeName('Αττικής!'), 'αττικης');
  const regions = await api('/api/regions');
  assert.equal(regions.status, 200);
  const regionRows = await regions.json();
  assert.equal(regionRows.length, 13);
  const regionalUnits = await api(`/api/regional-units?regionId=${regionRows.find((region) => region.name === 'Αττικής').id}`);
  assert.equal(regionalUnits.status, 200);
  assert.ok((await regionalUnits.json()).length > 0);
  const municipalities = await api('/api/municipalities/search?q=%CE%B1%CE%B8%CE%B7%CE%BD&limit=3');
  assert.ok((await municipalities.json()).some((municipality) => municipality.name === 'Αθηναίων'));
});

test('returns a postcode hierarchy and streets', async () => {
  const response = await api('/api/postcodes/10431');
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.hierarchy.municipality.name, 'Αθηναίων');
  assert.ok(result.streets.some((street) => street.name === 'Αγίου Κωνσταντίνου'));
  assert.equal((await api('/api/postcodes/1043')).status, 404);
});

test('validates fields independently and rejects malformed API input', async () => {
  const response = await api('/api/validate-address', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ postcode: '10431', street: 'Αγίου Κωνσταντίνου', houseNumber: 3, municipality: 'Αθην', region: 'Αττικ' }) });
  const result = await response.json();
  assert.equal(result.postcode.status, 'valid');
  assert.equal(result.street.status, 'valid');
  assert.equal(result.houseNumber.status, 'valid');
  assert.equal(result.municipality.status, 'valid');
  assert.equal(result.region.status, 'valid');
  const invalid = await api('/api/validate-address', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ postcode: '10431', street: 'Unknown street', houseNumber: 1 }) });
  assert.equal((await invalid.json()).houseNumber.status, 'not_evaluated');
  assert.equal((await api('/api/regional-units')).status, 400);
});

test('static demo includes all four documented controls', () => {
  const html = readFileSync(new URL('../public/index.html', import.meta.url), 'utf8');
  for (const id of ['postcode-form', 'region', 'regional-unit', 'municipality-search', 'address-form']) assert.match(html, new RegExp(`id="${id}"`, 'u'));
});
