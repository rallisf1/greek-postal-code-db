library;

import 'package:flutter/services.dart';
import 'package:greek_postal_code_db/greek_postal_code_db_internal.dart'
    show PostalCodeClient, createPostalCodeClientFromBytes;

export 'package:greek_postal_code_db/greek_postal_code_db.dart';

/// Opens the database declared as an asset by the core package.
Future<PostalCodeClient> createFlutterPostalCodeClient() async {
  final asset = await rootBundle
      .load('packages/greek_postal_code_db/lib/data/library.sqlite');
  return createPostalCodeClientFromBytes(Uint8List.sublistView(asset));
}
