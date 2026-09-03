import assert from 'node:assert/strict';
import test from 'node:test';
import { createPostalCodeClient } from '../dist/index.js';

test('lists, filters, and searches hierarchy entities', () => {
  const client = createPostalCodeClient();
  try {
    const regions = client.listRegions();
    assert.equal(regions.length, 13);
    assert.equal('officialCode' in regions[0], false);
    const attica = client.searchRegions('Αττικης');
    assert.equal(attica.length, 1);
    const regionalUnits = client.listRegionalUnits({ regionId: attica[0].id, includeOfficialCode: true });
    assert.ok(regionalUnits.length > 0);
    assert.ok('officialCode' in regionalUnits[0]);
    assert.ok(client.searchRegionalUnits('αθηνων', { regionId: attica[0].id, limit: 1 }).length <= 1);
    const municipalities = client.searchMunicipalities('Αθην', { include: { hierarchy: true } });
    assert.equal(municipalities[0]?.hierarchy?.regionalUnit?.name, 'Κεντρικού Τομέα Αθηνών');
    assert.equal(municipalities[0]?.hierarchy?.region?.name, 'Αττικής');
    assert.equal(municipalities[0]?.hierarchy?.decentralizedAdministration?.name, 'Αττικής');
  } finally { client.close(); }
});

test('looks up postcodes with optional hierarchy and streets', () => {
  const client = createPostalCodeClient();
  try {
    assert.equal(client.getPostcode('104 31'), null);
    assert.equal(client.getPostcode('99999'), null);
    const location = client.getPostcode('10431', { include: { hierarchy: true, streets: true } });
    assert.equal(location?.municipalityId, 1);
    assert.equal(location?.hierarchy?.municipality?.name, 'Αθηναίων');
    assert.ok(location?.streets?.some((street) => street.name === 'Αγίου Κωνσταντίνου'));
  } finally { client.close(); }
});

test('validates each supplied address component independently', () => {
  const client = createPostalCodeClient();
  try {
    const valid = client.validateAddress({ postcode: '10431', municipality: 'Αθην', region: 'Αττικ', street: 'Αγίου Κωνσταντίνου', houseNumber: 3 });
    assert.equal(valid.postcode.status, 'valid');
    assert.equal(valid.municipality?.status, 'valid');
    assert.equal(valid.region?.status, 'valid');
    assert.equal(valid.street?.status, 'valid');
    assert.equal(valid.houseNumber?.status, 'valid');
    const invalid = client.validateAddress({ postcode: '10431', street: 'Δεν Υπάρχει', houseNumber: 1, municipality: 'Θεσσαλονίκης' });
    assert.equal(invalid.street?.status, 'invalid');
    assert.equal(invalid.houseNumber?.status, 'not_evaluated');
    assert.equal(invalid.municipality?.status, 'invalid');
    assert.equal(client.validateAddress({ postcode: '10431', municipality: '' }).municipality?.status, 'invalid');
    assert.equal(client.validateAddress({ postcode: '10431', street: 'Βενιζέλου Ελευθερίου', houseNumber: 69 }).houseNumber?.status, 'valid');
    assert.equal(client.validateAddress({ postcode: '10431', street: 'Βενιζέλου Ελευθερίου', houseNumber: 67 }).houseNumber?.status, 'invalid');
    assert.equal(client.validateAddress({ postcode: '10431', street: 'Στοά ΙΚΑ', houseNumber: 5 }).houseNumber?.status, 'valid');
  } finally { client.close(); }
});

test('close prevents additional queries', () => {
  const client = createPostalCodeClient();
  client.close();
  assert.throws(() => client.listRegions(), /closed/u);
});
