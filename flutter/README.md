# Greek Postal Code DB for Flutter

Flutter-native adapter for `greek_postal_code_db`. It loads the core package's embedded SQLite database from the Flutter asset bundle.

```dart
import 'package:greek_postal_code_db_flutter/greek_postal_code_db_flutter.dart';

final client = await createFlutterPostalCodeClient();
final regions = client.listRegions();
await client.close();
```

Android, iOS, macOS, Windows, and Linux are supported. Flutter Web is not supported.
