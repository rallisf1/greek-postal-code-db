import { mkdirSync, writeFileSync } from 'node:fs';

const source = '../library.sqlite';
const output = '.generated/library.sql';
const dump = Bun.spawnSync(['sqlite3', source, '.dump']);
if (dump.exitCode !== 0) throw new Error(new TextDecoder().decode(dump.stderr));

const sourceSql = new TextDecoder().decode(dump.stdout)
  .split('\n')
  .filter((line) => !/^(PRAGMA foreign_keys=OFF;|BEGIN TRANSACTION;|COMMIT;)$/u.test(line))
  .join('\n');
const tables = ['streets', 'locations', 'municipal_units', 'communities', 'municipalities', 'regional_units', 'regions', 'decentralized_administrations'];
const indexes = [
  'CREATE INDEX IF NOT EXISTS idx_streets_postcode ON streets(postcode);',
  'CREATE INDEX IF NOT EXISTS idx_regional_units_region ON regional_units(region_id);',
  'CREATE INDEX IF NOT EXISTS idx_municipalities_regional_unit ON municipalities(regional_unit_id);',
  'CREATE INDEX IF NOT EXISTS idx_municipal_units_municipality ON municipal_units(municipality_id);',
  'CREATE INDEX IF NOT EXISTS idx_communities_municipality ON communities(municipality_id);'
];
const sql = [`PRAGMA foreign_keys=OFF;`, ...tables.map((table) => `DROP TABLE IF EXISTS "${table}";`), sourceSql, ...indexes, 'PRAGMA foreign_keys=ON;', ''].join('\n');

mkdirSync('.generated', { recursive: true });
writeFileSync(output, sql);

if (process.argv.includes('--validate')) {
  const validation = Bun.spawnSync(['sqlite3', ':memory:'], { stdin: new TextEncoder().encode(sql) });
  if (validation.exitCode !== 0) throw new Error(new TextDecoder().decode(validation.stderr));
}
