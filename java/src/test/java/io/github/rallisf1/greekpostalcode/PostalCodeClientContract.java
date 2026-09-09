package io.github.rallisf1.greekpostalcode;

import static io.github.rallisf1.greekpostalcode.Models.*;

/** Dependency-free contract checks run by Maven's test phase. */
public final class PostalCodeClientContract {
    public static void main(String[] args) {
        try (var client = PostalCodeClient.create()) {
            check(client.listRegions().size() == 13, "expected 13 regions");
            check(client.searchRegions("Αττικης", new ListOptions()).getFirst().name().equals("Αττικής"), "normalization search failed");
            var municipality = client.searchMunicipalities("Αθην", new MunicipalityOptions(null, null, true, false)).getFirst();
            check(municipality.hierarchy().regionalUnit().name().equals("Κεντρικού Τομέα Αθηνών"), "entity hierarchy failed");
            var postcode = client.getPostcode("10431", new PostcodeOptions(true, true));
            check(postcode.hierarchy().municipality().name().equals("Αθηναίων"), "postcode hierarchy failed");
            check(postcode.streets().stream().anyMatch(street -> street.name().equals("Αγίου Κωνσταντίνου")), "street lookup failed");
            var address = client.validateAddress(new AddressInput("10431", "Βενιζέλου Ελευθερίου", 69, LocalityReference.byName("Αθην"), null, null, null, null));
            check(address.postcode().status() == ValidationStatus.VALID && address.street().status() == ValidationStatus.VALID && address.houseNumber().status() == ValidationStatus.VALID && address.municipality().status() == ValidationStatus.VALID, "address validation failed");
        }
        System.out.println("Java client contract tests passed.");
    }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
