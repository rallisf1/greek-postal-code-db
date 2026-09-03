# @greek-postal-code-db/typescript

Read-only Greek postal-code data for Node.js 22.5+ and Bun. The published package includes its SQLite database.

```ts
import { createPostalCodeClient } from '@greek-postal-code-db/typescript';

const client = createPostalCodeClient();
const location = client.getPostcode('10431', { include: { hierarchy: true, streets: true } });
const municipalities = client.searchMunicipalities('Αθην', { include: { hierarchy: true } });
client.close();
```

All list and search methods accept `include: { hierarchy: true }` to attach their parent chain. See the exported TypeScript types for the complete API.
