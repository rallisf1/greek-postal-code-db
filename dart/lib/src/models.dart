enum ValidationStatus { valid, invalid, notEvaluated }

final class Entity {
  const Entity(this.id, this.name, {this.officialCode, this.hierarchy});
  final int id;
  final String name;
  final String? officialCode;
  final EntityHierarchy? hierarchy;
}

final class EntityHierarchy {
  const EntityHierarchy(
      {this.decentralizedAdministration,
      this.region,
      this.regionalUnit,
      this.municipality,
      this.municipalUnit,
      this.community});
  final Entity? decentralizedAdministration;
  final Entity? region;
  final Entity? regionalUnit;
  final Entity? municipality;
  final Entity? municipalUnit;
  final Entity? community;
}

final class Street {
  const Street(this.id, this.postcode, this.name,
      {this.oddStart, this.oddEnd, this.evenStart, this.evenEnd});
  final int id;
  final String postcode;
  final String name;
  final String? oddStart, oddEnd, evenStart, evenEnd;
}

final class PostcodeResult {
  const PostcodeResult(this.postcode,
      {this.latitude,
      this.longitude,
      this.localArea,
      this.municipalUnitId,
      this.communityId,
      this.municipalityId,
      this.hierarchy,
      this.streets});
  final String postcode;
  final double? latitude, longitude;
  final String? localArea;
  final int? municipalUnitId, communityId, municipalityId;
  final EntityHierarchy? hierarchy;
  final List<Street>? streets;
}

final class PostcodeInclude {
  const PostcodeInclude({this.hierarchy = false, this.streets = false});
  final bool hierarchy, streets;
}

sealed class LocalityReference {
  const LocalityReference();
}

final class LocalityId extends LocalityReference {
  const LocalityId(this.id);
  final int id;
}

final class LocalityName extends LocalityReference {
  const LocalityName(this.name);
  final String name;
}

final class AddressInput {
  const AddressInput(
      {required this.postcode,
      this.street,
      this.houseNumber,
      this.municipality,
      this.municipalUnit,
      this.community,
      this.regionalUnit,
      this.region});
  final String postcode;
  final String? street;
  final Object? houseNumber;
  final LocalityReference? municipality,
      municipalUnit,
      community,
      regionalUnit,
      region;
}

final class ValidationResult {
  const ValidationResult(this.status, this.input, {this.matches, this.reason});
  final ValidationStatus status;
  final Object? input;
  final List<Object?>? matches;
  final String? reason;
}

final class AddressValidation {
  const AddressValidation(
      {required this.postcode,
      this.street,
      this.houseNumber,
      this.municipality,
      this.municipalUnit,
      this.community,
      this.regionalUnit,
      this.region});
  final ValidationResult postcode;
  final ValidationResult? street,
      houseNumber,
      municipality,
      municipalUnit,
      community,
      regionalUnit,
      region;
}
