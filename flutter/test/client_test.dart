import 'package:flutter_test/flutter_test.dart';
import 'package:greek_postal_code_db_flutter/greek_postal_code_db_flutter.dart';

void main() {
  testWidgets('opens the core package asset', (tester) async {
    final client = await createFlutterPostalCodeClient();
    try {
      expect(client.searchRegions('Αττικης').single.name, 'Αττικής');
    } finally {
      await client.close();
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
