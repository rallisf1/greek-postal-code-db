# Greek Postal Code DB clients

Language clients for the Greek Postal Code DB. Each package embeds the same read-only `library.sqlite` asset and is versioned and published independently.

## Packages

- [`typescript`](./typescript): Node.js and Bun client, published as `@rallisf1/greek-postal-code-db`.
- [`models`](./models): private TypeScript types used internally; it is not published.

## Updating the data

The internal editor produces the database externally. Copy its reviewed export to `library.sqlite`, then bump every client package version that will publish the updated data. Client builds stage the root asset into their package artifacts.

## Development

Run TypeScript checks from its package directory:

```sh
cd typescript
bun install --frozen-lockfile
bun run test
```

GitHub Actions validates pull requests and publishes a new npm version after a version-bump merge to `main`.
