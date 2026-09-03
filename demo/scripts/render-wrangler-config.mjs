import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const required = ['CLOUDFLARE_PAGES_PROJECT', 'CLOUDFLARE_D1_DATABASE_NAME', 'CLOUDFLARE_D1_DATABASE_ID'];
for (const name of required) if (!process.env[name]) throw new Error(`${name} is required`);

const template = readFileSync('wrangler.toml.template', 'utf8');
const rendered = required.reduce((text, name) => text.replaceAll(`__${name}__`, process.env[name]), template);
mkdirSync('.generated', { recursive: true });
writeFileSync('.generated/wrangler.toml', rendered);
