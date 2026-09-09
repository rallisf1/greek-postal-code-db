import XCTest
@testable import GreekPostalCodeDB

final class PostalCodeClientTests: XCTestCase {
    func testListSearchAndHierarchy() throws {
        let client = try createPostalCodeClient()
        defer { try? client.close() }

        XCTAssertEqual(try client.listRegions().count, 13)
        XCTAssertEqual(try client.searchRegions("Αττικης").map { $0.name }, ["Αττικής"])
        XCTAssertEqual(try client.searchRegions("αττικησ!!").map { $0.name }, ["Αττικής"])
        XCTAssertThrowsError(try client.listRegions(options: .init(limit: 0)))

        let municipalities = try client.searchMunicipalities("Αθην", options: .init(includeHierarchy: true))
        XCTAssertEqual(municipalities.first?.hierarchy?["regionalUnit"]??.name, "Κεντρικού Τομέα Αθηνών")
        XCTAssertNil(try client.listRegions(options: .init(includeOfficialCode: true)).first?.officialCode)
    }

    func testPostcodeAndAddressValidation() throws {
        let client = try createPostalCodeClient()
        defer { try? client.close() }

        let postcode = try XCTUnwrap(client.getPostcode("10431", include: .init(hierarchy: true, streets: true)))
        XCTAssertEqual(postcode.hierarchy?["municipality"]??.name, "Αθηναίων")
        XCTAssertTrue(postcode.streets?.contains(where: { $0.name == "Αγίου Κωνσταντίνου" }) == true)
        XCTAssertNil(try client.getPostcode("123"))
        XCTAssertNil(try client.getPostcode("99999"))

        let valid = try client.validateAddress(.init(postcode: "10431", street: "Βενιζέλου Ελευθερίου", houseNumber: 69, municipality: .name("Αθην")))
        XCTAssertEqual(valid.postcode.status, .valid)
        XCTAssertEqual(valid.street?.status, .valid)
        XCTAssertEqual(valid.houseNumber?.status, .valid)
        XCTAssertEqual(valid.municipality?.status, .valid)

        let invalid = try client.validateAddress(.init(postcode: "10431", street: "Δεν Υπάρχει", houseNumber: 1))
        XCTAssertEqual(invalid.street?.status, .invalid)
        XCTAssertEqual(invalid.houseNumber?.status, .notEvaluated)
    }

    func testClosePreventsFurtherQueries() throws {
        let client = try createPostalCodeClient()
        try client.close()
        XCTAssertThrowsError(try client.listRegions())
    }
}
