# Greek Postal Code DB for Dart

Offline, read-only Greek postal-code data for native Dart platforms. For Flutter applications, use the companion `greek_postal_code_db_flutter` package so the bundled database is loaded from Flutter assets.

```dart
import 'package:greek_postal_code_db/greek_postal_code_db.dart';

final client = await createPostalCodeClient();
final result = client.getPostcode('10431', include: const PostcodeInclude(hierarchy: true));
await client.close();
```

All hierarchy list/search methods use named parent-ID, limit, hierarchy, and official-code options. `validateAddress` returns independent validation results; it has no aggregate validity flag. Flutter Web is unsupported.
