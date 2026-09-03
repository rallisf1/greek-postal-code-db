import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const baseRef = process.argv[2];
if (!baseRef) throw new Error('Usage: node scripts/verify-typescript-version-bump.mjs <base-ref>');

const changedFiles = execFileSync('git', ['diff', '--name-only', `${baseRef}...HEAD`], { encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);
const publishableChange = changedFiles.some((file) => file === 'library.sqlite' || file.startsWith('typescript/') || file.startsWith('models/'));

if (!publishableChange) process.exit(0);

const current = JSON.parse(readFileSync('typescript/package.json', 'utf8')).version;
const previous = JSON.parse(execFileSync('git', ['show', `${baseRef}:typescript/package.json`], { encoding: 'utf8' })).version;

const semver = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
function parse(version) {
  const match = semver.exec(version);
  if (!match) throw new Error(`Invalid semantic version: ${version}`);
  return { numbers: match.slice(1, 4).map(Number), prerelease: match[4]?.split('.') ?? [] };
}
function compareIdentifier(left, right) {
  const leftNumeric = /^\d+$/u.test(left), rightNumeric = /^\d+$/u.test(right);
  if (leftNumeric && rightNumeric) return Number(left) - Number(right);
  if (leftNumeric) return -1;
  if (rightNumeric) return 1;
  return left.localeCompare(right);
}
function compare(left, right) {
  const a = parse(left), b = parse(right);
  for (let index = 0; index < a.numbers.length; index += 1) {
    if (a.numbers[index] !== b.numbers[index]) return a.numbers[index] - b.numbers[index];
  }
  if (!a.prerelease.length && !b.prerelease.length) return 0;
  if (!a.prerelease.length) return 1;
  if (!b.prerelease.length) return -1;
  for (let index = 0; index < Math.max(a.prerelease.length, b.prerelease.length); index += 1) {
    if (a.prerelease[index] === undefined) return -1;
    if (b.prerelease[index] === undefined) return 1;
    const result = compareIdentifier(a.prerelease[index], b.prerelease[index]);
    if (result !== 0) return result;
  }
  return 0;
}

if (compare(current, previous) <= 0) {
  throw new Error(`typescript/package.json version must increase for publishable changes (${previous} -> ${current}).`);
}
