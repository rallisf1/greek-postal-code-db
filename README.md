# Greek Postal Code DB clients

Language clients for the Greek Postal Code DB. Each package embeds the same read-only `library.sqlite` asset and is versioned and published independently.

## Features

- 1328 postal codes with hierarchy information (region, municipality, community, etc)
- partial street database (which street and numbers belong to each postal code)
- official government codes from Kallikratis (WIP)
- sqlite database included for offline use
- list / get / search / validateAddress functions

## Packages

- [`typescript`](./typescript): Node.js and Bun client, published as `@rallisf1/greek-postal-code-db`.
- [`php`](./php): PHP 8.1+ Composer client, published from this repository root as `rallisf1/greek-postal-code-db`.
- [`models`](./models): private TypeScript types used internally; it is not published.
- [`demo`](./demo): internal Cloudflare Pages/D1 demo application; it is not published.

## Contributing

### Packages

These packages have been almost entirely AI generated. Bug fixes through PRs are welcome. For new features open an issue first, as it has to be implemented in all clients.

### Dataset

PRs for `./library.sqlite` are welcome as long as they are accompanied with the changes in SQL format.

## Data sources used

- ELTA street search form
- OpencartGreece Post Code API
- Central Association of chambers of commerce in Greece (GEMI)
- data.gov.gr
- locationiq.com
