package postalcode

import (
	"context"
	"testing"
)

func TestListSearchAndHierarchy(t *testing.T) {
	client, err := NewClient()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	regions, err := client.ListRegions(context.Background(), ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(regions) != 13 {
		t.Fatalf("got %d regions, want 13", len(regions))
	}
	attica, err := client.SearchRegions(context.Background(), "Αττικης", ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(attica) != 1 || attica[0].Name != "Αττικής" {
		t.Fatalf("unexpected search result: %#v", attica)
	}
	municipalities, err := client.SearchMunicipalities(context.Background(), "Αθην", MunicipalityOptions{ListOptions: ListOptions{IncludeHierarchy: true}})
	if err != nil {
		t.Fatal(err)
	}
	if municipalities[0].Hierarchy["regionalUnit"].Name != "Κεντρικού Τομέα Αθηνών" {
		t.Fatalf("unexpected hierarchy: %#v", municipalities[0].Hierarchy)
	}
}

func TestPostcodeAndAddressValidation(t *testing.T) {
	client, err := NewClient()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	postcode, err := client.GetPostcode(context.Background(), "10431", PostcodeOptions{IncludeHierarchy: true, IncludeStreets: true})
	if err != nil {
		t.Fatal(err)
	}
	if postcode == nil || postcode.Hierarchy["municipality"].Name != "Αθηναίων" {
		t.Fatalf("unexpected postcode: %#v", postcode)
	}
	foundStreet := false
	for _, street := range postcode.Streets {
		foundStreet = foundStreet || street.Name == "Αγίου Κωνσταντίνου"
	}
	if !foundStreet {
		t.Fatal("expected Αγίου Κωνσταντίνου")
	}
	street := "Βενιζέλου Ελευθερίου"
	validation, err := client.ValidateAddress(context.Background(), AddressInput{Postcode: "10431", Street: &street, HouseNumber: 69, Municipality: "Αθην"})
	if err != nil {
		t.Fatal(err)
	}
	if validation.Postcode.Status != Valid || validation.HouseNumber.Status != Valid || validation.Municipality.Status != Valid {
		t.Fatalf("unexpected validation: %#v", validation)
	}
	missingStreet := "Δεν Υπάρχει"
	invalid, err := client.ValidateAddress(context.Background(), AddressInput{Postcode: "10431", Street: &missingStreet, HouseNumber: 1})
	if err != nil {
		t.Fatal(err)
	}
	if invalid.Street.Status != Invalid || invalid.HouseNumber.Status != NotEvaluated {
		t.Fatalf("unexpected invalid result: %#v", invalid)
	}
}

func TestClosePreventsQueries(t *testing.T) {
	client, err := NewClient()
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := client.ListRegions(context.Background(), ListOptions{}); err == nil {
		t.Fatal("expected closed-client error")
	}
}
