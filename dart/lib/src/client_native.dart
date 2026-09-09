import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

Future<PostalCodeClient> createPostalCodeClient() async {
  final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:greek_postal_code_db/data/library.sqlite'));
  if (uri == null || uri.scheme != 'file')
    throw StateError('The bundled library.sqlite resource is unavailable.');
  return createPostalCodeClientFromBytes(await File.fromUri(uri).readAsBytes());
}

/// Internal integration point used by the Flutter adapter. Not a database-path override API.
Future<PostalCodeClient> createPostalCodeClientFromBytes(
    Uint8List bytes) async {
  final file = await File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}greek-postal-code-db-${DateTime.now().microsecondsSinceEpoch}.sqlite')
      .create();
  await file.writeAsBytes(bytes, flush: true);
  final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
  database.execute('PRAGMA query_only = ON');
  return PostalCodeClient._(database, file);
}

final class PostalCodeClient {
  PostalCodeClient._(this._database, this._file);
  Database? _database;
  final File _file;
  Database get _db =>
      _database ?? (throw StateError('PostalCodeClient is closed.'));
  Future<void> close() async {
    _database?.dispose();
    _database = null;
    if (await _file.exists()) await _file.delete();
  }

  List<Entity> listRegions({int? limit, bool includeHierarchy = false}) =>
      _list('regions', null, null, limit, includeHierarchy, false);
  List<Entity> listRegionalUnits(
          {int? regionId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _list('regional_units', 'region_id', regionId, limit, includeHierarchy,
          includeOfficialCode);
  List<Entity> listMunicipalities(
          {int? regionalUnitId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _list('municipalities', 'regional_unit_id', regionalUnitId, limit,
          includeHierarchy, includeOfficialCode);
  List<Entity> listMunicipalUnits(
          {int? municipalityId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _list('municipal_units', 'municipality_id', municipalityId, limit,
          includeHierarchy, includeOfficialCode);
  List<Entity> listCommunities(
          {int? municipalityId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _list('communities', 'municipality_id', municipalityId, limit,
          includeHierarchy, includeOfficialCode);
  List<Entity> searchRegions(String query,
          {int? limit, bool includeHierarchy = false}) =>
      _search('regions', null, query, null, limit, includeHierarchy, false);
  List<Entity> searchRegionalUnits(String query,
          {int? regionId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _search('regional_units', 'region_id', query, regionId, limit,
          includeHierarchy, includeOfficialCode);
  List<Entity> searchMunicipalities(String query,
          {int? regionalUnitId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _search('municipalities', 'regional_unit_id', query, regionalUnitId,
          limit, includeHierarchy, includeOfficialCode);
  List<Entity> searchMunicipalUnits(String query,
          {int? municipalityId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _search('municipal_units', 'municipality_id', query, municipalityId,
          limit, includeHierarchy, includeOfficialCode);
  List<Entity> searchCommunities(String query,
          {int? municipalityId,
          int? limit,
          bool includeHierarchy = false,
          bool includeOfficialCode = false}) =>
      _search('communities', 'municipality_id', query, municipalityId, limit,
          includeHierarchy, includeOfficialCode);

  PostcodeResult? getPostcode(String postcode,
      {PostcodeInclude include = const PostcodeInclude()}) {
    if (!RegExp(r'^\d{5}$').hasMatch(postcode)) return null;
    final row = _one(
        'SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?',
        [postcode]);
    if (row == null) return null;
    final value = _postcode(row);
    return PostcodeResult(value.postcode,
        latitude: value.latitude,
        longitude: value.longitude,
        localArea: value.localArea,
        municipalUnitId: value.municipalUnitId,
        communityId: value.communityId,
        municipalityId: value.municipalityId,
        hierarchy: include.hierarchy ? _postcodeHierarchy(value) : null,
        streets: include.streets ? _streets(postcode) : null);
  }

  AddressValidation validateAddress(AddressInput input) {
    final postcode = getPostcode(input.postcode,
        include: PostcodeInclude(
            hierarchy: true,
            streets: input.street != null || input.houseNumber != null));
    final postResult = !RegExp(r'^\d{5}$').hasMatch(input.postcode)
        ? _invalid(input.postcode, 'postcode_must_be_exactly_five_digits')
        : postcode == null
            ? _invalid(input.postcode, 'postcode_not_found')
            : _valid(input.postcode, [postcode]);
    if (postcode == null)
      return AddressValidation(
          postcode: postResult,
          street: _ne(input.street),
          houseNumber: _ne(input.houseNumber),
          municipality: _ne(input.municipality),
          municipalUnit: _ne(input.municipalUnit),
          community: _ne(input.community),
          regionalUnit: _ne(input.regionalUnit),
          region: _ne(input.region));
    final h = postcode.hierarchy!;
    final street = input.street == null
        ? null
        : _streetValidation(input.street!, postcode.streets!);
    return AddressValidation(
        postcode: postResult,
        street: street,
        houseNumber: input.houseNumber == null
            ? null
            : _houseValidation(input.houseNumber!, street),
        municipality: input.municipality == null
            ? null
            : _reference('municipalities', input.municipality!, h.municipality),
        municipalUnit: input.municipalUnit == null
            ? null
            : _reference(
                'municipal_units', input.municipalUnit!, h.municipalUnit),
        community: input.community == null
            ? null
            : _reference('communities', input.community!, h.community),
        regionalUnit: input.regionalUnit == null
            ? null
            : _reference('regional_units', input.regionalUnit!, h.regionalUnit),
        region: input.region == null
            ? null
            : _reference('regions', input.region!, h.region));
  }

  List<Entity> _list(String table, String? parent, int? parentId, int? limit,
      bool hierarchy, bool official) {
    if (limit != null && limit <= 0)
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    final sql =
        'SELECT id, name${official ? ', official_code' : ''} FROM $table${parent != null && parentId != null ? ' WHERE $parent = ?' : ''} ORDER BY name, id';
    var values = _db
        .select(sql, parent != null && parentId != null ? [parentId] : [])
        .map((r) => _entity(r, official))
        .toList();
    if (hierarchy)
      values = values
          .map((v) => Entity(v.id, v.name,
              officialCode: v.officialCode,
              hierarchy: _entityHierarchy(table, v.id)))
          .toList();
    return limit == null ? values : values.take(limit).toList();
  }

  List<Entity> _search(String table, String? parent, String query,
      int? parentId, int? limit, bool hierarchy, bool official) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return [];
    var values = _list(table, parent, parentId, null, hierarchy, official)
        .where((v) => _normalize(v.name).startsWith(normalized))
        .toList();
    return limit == null ? values : values.take(limit).toList();
  }

  EntityHierarchy _entityHierarchy(String table, int id) {
    if (table == 'regions')
      return EntityHierarchy(
          decentralizedAdministration: _entityOrNull(
              _one(
                  'SELECT da.id, da.name FROM regions r JOIN decentralized_administrations da ON da.id=r.decentralized_administration_id WHERE r.id=?',
                  [id]),
              false));
    if (table == 'regional_units') return _regionalUnitHierarchy(id);
    if (table == 'municipalities') return _municipalityHierarchy(id);
    final row = _one('SELECT municipality_id FROM $table WHERE id=?', [id]);
    return row == null
        ? const EntityHierarchy()
        : _municipalityChildHierarchy(row['municipality_id'] as int);
  }

  EntityHierarchy _postcodeHierarchy(PostcodeResult p) {
    final municipality = p.municipalityId == null
        ? null
        : _entityOrNull(
            _one('SELECT id,name,official_code FROM municipalities WHERE id=?',
                [p.municipalityId]),
            true);
    final parent = municipality == null
        ? const EntityHierarchy()
        : _municipalityHierarchy(municipality.id);
    return EntityHierarchy(
        decentralizedAdministration: parent.decentralizedAdministration,
        region: parent.region,
        regionalUnit: parent.regionalUnit,
        municipality: municipality,
        municipalUnit: p.municipalUnitId == null
            ? null
            : _entityOrNull(
                _one(
                    'SELECT id,name,official_code FROM municipal_units WHERE id=?',
                    [
                      p.municipalUnitId
                    ]),
                true),
        community: p.communityId == null
            ? null
            : _entityOrNull(
                _one('SELECT id,name,official_code FROM communities WHERE id=?',
                    [p.communityId]),
                true));
  }

  EntityHierarchy _regionalUnitHierarchy(int id) => EntityHierarchy(
      region: _entityOrNull(
          _one(
              'SELECT r.id,r.name FROM regional_units u JOIN regions r ON r.id=u.region_id WHERE u.id=?',
              [
                id
              ]),
          false),
      decentralizedAdministration: _entityOrNull(
          _one(
              'SELECT d.id,d.name FROM regional_units u JOIN regions r ON r.id=u.region_id JOIN decentralized_administrations d ON d.id=r.decentralized_administration_id WHERE u.id=?',
              [id]),
          false));
  EntityHierarchy _municipalityHierarchy(int id) {
    final unit = _entityOrNull(
        _one(
            'SELECT u.id,u.name,u.official_code FROM municipalities m JOIN regional_units u ON u.id=m.regional_unit_id WHERE m.id=?',
            [id]),
        true);
    final parent = unit == null
        ? const EntityHierarchy()
        : _regionalUnitHierarchy(unit.id);
    return EntityHierarchy(
        decentralizedAdministration: parent.decentralizedAdministration,
        region: parent.region,
        regionalUnit: unit);
  }

  EntityHierarchy _municipalityChildHierarchy(int id) {
    final m = _entityOrNull(
        _one('SELECT id,name,official_code FROM municipalities WHERE id=?',
            [id]),
        true);
    final p =
        m == null ? const EntityHierarchy() : _municipalityHierarchy(m.id);
    return EntityHierarchy(
        decentralizedAdministration: p.decentralizedAdministration,
        region: p.region,
        regionalUnit: p.regionalUnit,
        municipality: m);
  }

  List<Street> _streets(String postcode) => _db
      .select(
          'SELECT id,postcode,name,odd_start,odd_end,even_start,even_end FROM streets WHERE postcode=? ORDER BY name,id',
          [
            postcode
          ])
      .map((r) => Street(
          r['id'] as int, r['postcode'] as String, r['name'] as String,
          oddStart: r['odd_start'] as String?,
          oddEnd: r['odd_end'] as String?,
          evenStart: r['even_start'] as String?,
          evenEnd: r['even_end'] as String?))
      .toList();
  ValidationResult _reference(
      String table, LocalityReference ref, Entity? linked) {
    final official = table != 'regions';
    final List<Entity> matches;
    if (ref is LocalityId) {
      matches = _db
          .select(
              'SELECT id,name${official ? ',official_code' : ''} FROM $table WHERE id=?',
              [ref.id])
          .map((r) => _entity(r, official))
          .toList();
    } else {
      final name = (ref as LocalityName).name;
      if (_normalize(name).isEmpty)
        return _invalid(ref, 'reference_must_not_be_empty', []);
      matches = _list(table, null, null, null, false, official)
          .where((v) => _normalize(v.name).startsWith(_normalize(name)))
          .toList();
    }
    if (linked == null)
      return _invalid(ref, 'postcode_has_no_linked_entity', matches);
    return matches.any((v) => v.id == linked.id)
        ? _valid(ref, matches)
        : _invalid(ref, null, matches);
  }

  ValidationResult _streetValidation(String name, List<Street> streets) {
    final matches =
        streets.where((s) => _normalize(s.name) == _normalize(name)).toList();
    return matches.isEmpty
        ? _invalid(name, 'street_not_found_for_postcode', matches)
        : _valid(name, matches);
  }

  ValidationResult _houseValidation(Object value, ValidationResult? street) {
    if (street?.status != ValidationStatus.valid)
      return _notEvaluated(value, 'street_is_required_and_must_be_valid');
    final number = value is int && value > 0
        ? value
        : value is String &&
                RegExp(r'^\d+$').hasMatch(value) &&
                int.tryParse(value)! > 0
            ? int.parse(value)
            : null;
    if (number == null)
      return _invalid(value, 'house_number_must_be_a_positive_integer');
    final streets = street!.matches!.cast<Street>();
    final checks =
        streets.map((s) => _contains(s, number)).whereType<bool>().toList();
    return checks.isEmpty || checks.contains(true)
        ? _valid(value, streets,
            checks.isEmpty ? 'street_has_no_usable_range' : null)
        : _invalid(value, null, streets);
  }

  bool? _contains(Street s, int n) {
    final start = n.isEven ? s.evenStart : s.oddStart;
    final end = n.isEven ? s.evenEnd : s.oddEnd;
    final first = _range(start);
    if (first == null) return null;
    if (_normalize(end ?? '') == 'τελ') return n >= first;
    final last = _range(end);
    return last == null ? null : n >= first && n <= last;
  }

  int? _range(String? text) {
    final value = RegExp(r'^\s*(\d+)').firstMatch(text ?? '')?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  Row? _one(String sql, List<Object?> args) {
    final rows = _db.select(sql, args);
    return rows.isEmpty ? null : rows.first;
  }

  Entity _entity(Row row, bool official) =>
      Entity(row['id'] as int, row['name'] as String,
          officialCode: official ? row['official_code'] as String? : null);
  Entity? _entityOrNull(Row? row, bool official) =>
      row == null ? null : _entity(row, official);
  PostcodeResult _postcode(Row r) => PostcodeResult(r['postcode'] as String,
      latitude: r['latitude'] as double?,
      longitude: r['longitude'] as double?,
      localArea: r['local_area'] as String?,
      municipalUnitId: r['municipal_unit_id'] as int?,
      communityId: r['community_id'] as int?,
      municipalityId: r['municipality_id'] as int?);
}

ValidationResult _valid(Object? input, List<Object?> values,
        [String? reason]) =>
    ValidationResult(ValidationStatus.valid, input,
        matches: values, reason: reason);
ValidationResult _invalid(Object? input, String? reason,
        [List<Object?>? values]) =>
    ValidationResult(ValidationStatus.invalid, input,
        matches: values, reason: reason);
ValidationResult? _ne(Object? input) =>
    input == null ? null : _notEvaluated(input, 'postcode_not_found');
ValidationResult _notEvaluated(Object input, String reason) =>
    ValidationResult(ValidationStatus.notEvaluated, input, reason: reason);
String _normalize(String value) {
  const accents = {
    'ά': 'α',
    'έ': 'ε',
    'ή': 'η',
    'ί': 'ι',
    'ό': 'ο',
    'ύ': 'υ',
    'ώ': 'ω',
    'ϊ': 'ι',
    'ϋ': 'υ',
    'ΐ': 'ι',
    'ΰ': 'υ',
    'ς': 'σ'
  };
  final out = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final c = String.fromCharCode(rune);
    final mapped = accents[c] ?? c;
    final n = mapped.codeUnitAt(0);
    if ((n >= 48 && n <= 57) ||
        (n >= 97 && n <= 122) ||
        (n >= 0x370 && n <= 0x3ff)) out.write(mapped);
  }
  return out.toString();
}
