import 'package:greek_postal_code_db/greek_postal_code_db.dart';
import 'package:test/test.dart';

void main() {
  test('core client contract', () async {
    final client = await createPostalCodeClient();
    try {
      if (client.listRegions().length != 13)
        throw StateError('Expected 13 regions.');
      if (client.searchRegions('Αττικης').single.name != 'Αττικής')
        throw StateError('Greek normalization failed.');
      final municipality =
          client.searchMunicipalities('Αθην', includeHierarchy: true).first;
      if (municipality.hierarchy?.regionalUnit?.name !=
          'Κεντρικού Τομέα Αθηνών')
        throw StateError('Entity hierarchy failed.');
      final postcode = client.getPostcode('10431',
          include: const PostcodeInclude(hierarchy: true, streets: true));
      if (postcode?.hierarchy?.municipality?.name != 'Αθηναίων' ||
          !(postcode!.streets!.any((s) => s.name == 'Αγίου Κωνσταντίνου')))
        throw StateError('Postcode lookup failed.');
      final valid = client.validateAddress(const AddressInput(
          postcode: '10431',
          street: 'Βενιζέλου Ελευθερίου',
          houseNumber: 69,
          municipality: LocalityName('Αθην')));
      if (valid.postcode.status != ValidationStatus.valid ||
          valid.street?.status != ValidationStatus.valid ||
          valid.houseNumber?.status != ValidationStatus.valid ||
          valid.municipality?.status != ValidationStatus.valid)
        throw StateError('Address validation failed.');
      final invalid = client.validateAddress(const AddressInput(
          postcode: '10431', street: 'Δεν Υπάρχει', houseNumber: 1));
      if (invalid.street?.status != ValidationStatus.invalid ||
          invalid.houseNumber?.status != ValidationStatus.notEvaluated)
        throw StateError('Dependent validation failed.');
    } finally {
      await client.close();
    }
  });
}
