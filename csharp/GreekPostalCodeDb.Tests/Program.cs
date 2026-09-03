using GreekPostalCodeDb;

using var client = PostalCodeClient.Create();
var regions = client.ListRegions();
Assert(regions.Count == 13, "expected 13 regions");
Assert(client.SearchRegions("Αττικης").Single().Name == "Αττικής", "normalization search failed");
Assert(client.SearchMunicipalities("Α", new(Limit: 1)).Count == 1, "search limit failed");
var municipality = client.SearchMunicipalities("Αθην", new(IncludeHierarchy: true)).First();
Assert(municipality.Hierarchy?.RegionalUnit?.Name == "Κεντρικού Τομέα Αθηνών", "entity hierarchy failed");
var postcode = client.GetPostcode("10431", new(true, true));
Assert(postcode?.Hierarchy?.Municipality?.Name == "Αθηναίων", "postcode hierarchy failed");
Assert(postcode!.Streets!.Any(street => street.Name == "Αγίου Κωνσταντίνου"), "postcode streets failed");
var address = client.ValidateAddress(new("10431", "Βενιζέλου Ελευθερίου", 69, LocalityReference.ByName("Αθην")));
Assert(address.Postcode.Status == ValidationStatus.Valid && address.Street?.Status == ValidationStatus.Valid && address.HouseNumber?.Status == ValidationStatus.Valid && address.Municipality?.Status == ValidationStatus.Valid, "address validation failed");
var invalid = client.ValidateAddress(new("10431", "Δεν Υπάρχει", 1));
Assert(invalid.Street?.Status == ValidationStatus.Invalid && invalid.HouseNumber?.Status == ValidationStatus.NotEvaluated, "dependency validation failed");
client.Dispose();
try { client.ListRegions(); throw new Exception("closed client did not throw"); } catch (ObjectDisposedException) { }
Console.WriteLine("C# client contract tests passed.");

static void Assert(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}
