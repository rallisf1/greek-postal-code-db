import 'models.dart';

Future<PostalCodeClient> createPostalCodeClient() => throw UnsupportedError(
    'greek_postal_code_db does not support Web; use a native Dart or Flutter platform.');

final class PostalCodeClient {
  Never _unsupported() =>
      throw UnsupportedError('greek_postal_code_db does not support Web.');
  Future<void> close() async => _unsupported();
  List<Entity> listRegions({int? limit, bool includeHierarchy = false}) =>
      _unsupported();
  List<Entity> listRegionalUnits({int? regionId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> listMunicipalities({int? regionalUnitId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> listMunicipalUnits({int? municipalityId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> listCommunities({int? municipalityId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> searchRegions(String query, {int? limit, bool includeHierarchy = false}) => _unsupported();
  List<Entity> searchRegionalUnits(String query, {int? regionId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> searchMunicipalities(String query, {int? regionalUnitId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> searchMunicipalUnits(String query, {int? municipalityId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  List<Entity> searchCommunities(String query, {int? municipalityId, int? limit, bool includeHierarchy = false, bool includeOfficialCode = false}) => _unsupported();
  PostcodeResult? getPostcode(String postcode, {PostcodeInclude include = const PostcodeInclude()}) => _unsupported();
  AddressValidation validateAddress(AddressInput input) => _unsupported();
}
