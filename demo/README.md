# Greek Postal Code DB demo

Internal Cloudflare Pages and D1 demo application. It is not a published library or a supported public API.

## Local checks

```sh
bun install
bun run test
bun run validate:snapshot
```

`validate:snapshot` converts `../library.sqlite` to a D1-compatible SQL snapshot and validates it with SQLite. The GitHub workflow additionally imports that snapshot through Wrangler's local D1 mode.

## Cloudflare setup

Create a Cloudflare Pages project and a D1 database, then configure these GitHub repository variables:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_PAGES_PROJECT`
- `CLOUDFLARE_D1_DATABASE_NAME`
- `CLOUDFLARE_D1_DATABASE_ID`

Configure `CLOUDFLARE_API_TOKEN` as a repository secret with only the D1 and Pages permissions required by those resources. Run the `Demo` workflow manually with **Refresh D1** enabled for the initial import. Thereafter, a change to `library.sqlite` refreshes D1 automatically before Pages deploys.
