import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Opens an offline, read-only client backed by the database embedded in this
/// Swift package. The temporary materialized database is removed by `close()`.
public func createPostalCodeClient() throws -> PostalCodeClient {
    try PostalCodeClient()
}

public final class PostalCodeClient: @unchecked Sendable {
    private var database: OpaquePointer?
    private let temporaryDatabaseURL: URL

    init() throws {
        guard let resource = Bundle.module.url(forResource: "library", withExtension: "sqlite") else {
            throw PostalCodeClientError.bundledDatabaseUnavailable
        }
        temporaryDatabaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("greek-postal-code-db-\(UUID().uuidString).sqlite")
        do {
            try FileManager.default.copyItem(at: resource, to: temporaryDatabaseURL)
        } catch {
            throw PostalCodeClientError.database("Could not materialize the bundled database: \(error.localizedDescription)")
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(temporaryDatabaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            try? FileManager.default.removeItem(at: temporaryDatabaseURL)
            throw PostalCodeClientError.database("Could not open the bundled database read-only.")
        }
        database = handle
    }

    deinit { try? close() }

    /// Closes the SQLite handle and removes the temporary database copy. It is safe to call more than once.
    public func close() throws {
        if let database {
            let result = sqlite3_close_v2(database)
            guard result == SQLITE_OK else { throw databaseError(database) }
            self.database = nil
        }
        try? FileManager.default.removeItem(at: temporaryDatabaseURL)
    }

    public func listRegions(options: EntityOptions = .init()) throws -> [Entity] {
        try list(table: .regions, parentID: nil, options: options)
    }
    public func listRegionalUnits(regionID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try list(table: .regionalUnits, parentID: regionID, options: options)
    }
    public func listMunicipalities(regionalUnitID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try list(table: .municipalities, parentID: regionalUnitID, options: options)
    }
    public func listMunicipalUnits(municipalityID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try list(table: .municipalUnits, parentID: municipalityID, options: options)
    }
    public func listCommunities(municipalityID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try list(table: .communities, parentID: municipalityID, options: options)
    }

    public func searchRegions(_ query: String, options: EntityOptions = .init()) throws -> [Entity] {
        try search(table: .regions, query: query, parentID: nil, options: options)
    }
    public func searchRegionalUnits(_ query: String, regionID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try search(table: .regionalUnits, query: query, parentID: regionID, options: options)
    }
    public func searchMunicipalities(_ query: String, regionalUnitID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try search(table: .municipalities, query: query, parentID: regionalUnitID, options: options)
    }
    public func searchMunicipalUnits(_ query: String, municipalityID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try search(table: .municipalUnits, query: query, parentID: municipalityID, options: options)
    }
    public func searchCommunities(_ query: String, municipalityID: Int64? = nil, options: EntityOptions = .init()) throws -> [Entity] {
        try search(table: .communities, query: query, parentID: municipalityID, options: options)
    }

    public func getPostcode(_ postcode: String, include: PostcodeInclude = .init()) throws -> PostcodeResult? {
        guard postcode.isFiveDigits else { return nil }
        let rows = try query("SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?", [.text(postcode)])
        guard let row = rows.first else { return nil }
        var result = decodePostcode(from: row)
        if include.hierarchy { result = try withHierarchy(result) }
        if include.streets { result = PostcodeResult(postcode: result.postcode, latitude: result.latitude, longitude: result.longitude, localArea: result.localArea, municipalUnitID: result.municipalUnitID, communityID: result.communityID, municipalityID: result.municipalityID, hierarchy: result.hierarchy, streets: try streets(for: postcode)) }
        return result
    }

    public func validateAddress(_ input: AddressInput) throws -> AddressValidation {
        let postcode = try getPostcode(input.postcode, include: .init(hierarchy: true, streets: input.street != nil || input.houseNumber != nil))
        let postcodeResult: ValidationResult
        if !input.postcode.isFiveDigits {
            postcodeResult = .init(status: .invalid, input: .text(input.postcode), matches: nil, reason: "postcode_must_be_exactly_five_digits")
        } else if let postcode {
            postcodeResult = .init(status: .valid, input: .text(input.postcode), matches: .postcodes([postcode]), reason: nil)
        } else {
            postcodeResult = .init(status: .invalid, input: .text(input.postcode), matches: nil, reason: "postcode_not_found")
        }
        guard let postcode else {
            return .init(postcode: postcodeResult,
                         street: input.street.map { notEvaluated(.text($0), "postcode_not_found") },
                         houseNumber: input.houseNumber.map { notEvaluated(.integer($0), "postcode_not_found") },
                         municipality: input.municipality.map { notEvaluated(.locality($0), "postcode_not_found") },
                         municipalUnit: input.municipalUnit.map { notEvaluated(.locality($0), "postcode_not_found") },
                         community: input.community.map { notEvaluated(.locality($0), "postcode_not_found") },
                         regionalUnit: input.regionalUnit.map { notEvaluated(.locality($0), "postcode_not_found") },
                         region: input.region.map { notEvaluated(.locality($0), "postcode_not_found") })
        }
        let hierarchy = postcode.hierarchy ?? [:]
        let municipality = try input.municipality.map { try validateReference($0, table: .municipalities, linked: hierarchy["municipality"] ?? nil) }
        let municipalUnit = try input.municipalUnit.map { try validateReference($0, table: .municipalUnits, linked: hierarchy["municipalUnit"] ?? nil) }
        let community = try input.community.map { try validateReference($0, table: .communities, linked: hierarchy["community"] ?? nil) }
        let regionalUnit = try input.regionalUnit.map { try validateReference($0, table: .regionalUnits, linked: hierarchy["regionalUnit"] ?? nil) }
        let region = try input.region.map { try validateReference($0, table: .regions, linked: hierarchy["region"] ?? nil) }
        let street = input.street.map { validateStreet($0, streets: postcode.streets ?? []) }
        let houseNumber: ValidationResult?
        if let number = input.houseNumber {
            if street?.status != .valid {
                houseNumber = notEvaluated(.integer(number), "street_is_required_and_must_be_valid")
            } else if number <= 0 {
                houseNumber = .init(status: .invalid, input: .integer(number), matches: nil, reason: "house_number_must_be_a_positive_integer")
            } else {
                let matchedStreets = streetMatches(street)
                let applicability = matchedStreets.compactMap { $0.contains(number: number) }
                houseNumber = .init(status: applicability.isEmpty || applicability.contains(true) ? .valid : .invalid, input: .integer(number), matches: .streets(matchedStreets), reason: applicability.isEmpty ? "street_has_no_usable_range" : nil)
            }
        } else { houseNumber = nil }
        return .init(postcode: postcodeResult, street: street, houseNumber: houseNumber, municipality: municipality, municipalUnit: municipalUnit, community: community, regionalUnit: regionalUnit, region: region)
    }
}

private extension PostalCodeClient {
    enum Table: String {
        case regions = "regions", regionalUnits = "regional_units", municipalities, municipalUnits = "municipal_units", communities
        var parentColumn: String? {
            switch self { case .regions: nil; case .regionalUnits: "region_id"; case .municipalities: "regional_unit_id"; case .municipalUnits, .communities: "municipality_id" }
        }
        var supportsOfficialCode: Bool { self != .regions }
    }
    enum Value { case text(String), integer(Int64) }

    func list(table: Table, parentID: Int64?, options: EntityOptions) throws -> [Entity] {
        try checkLimit(options.limit)
        let wantsCode = options.includeOfficialCode && table.supportsOfficialCode
        var sql = "SELECT id, name\(wantsCode ? ", official_code" : "") FROM \(table.rawValue)"
        var values: [Value] = []
        if let parentID, let column = table.parentColumn { sql += " WHERE \(column) = ?"; values.append(.integer(parentID)) }
        sql += " ORDER BY name, id"
        var entities = try query(sql, values).map { entity(from: $0, hasOfficialCode: wantsCode) }
        if let limit = options.limit { entities = Array(entities.prefix(limit)) }
        if options.includeHierarchy { entities = try entities.map { try withHierarchy($0, table: table) } }
        return entities
    }

    func search(table: Table, query search: String, parentID: Int64?, options: EntityOptions) throws -> [Entity] {
        try checkLimit(options.limit)
        let normalized = normalize(search)
        guard !normalized.isEmpty else { return [] }
        var allOptions = options; allOptions.limit = nil; allOptions.includeHierarchy = false
        var entities = try list(table: table, parentID: parentID, options: allOptions).filter { normalize($0.name).hasPrefix(normalized) }
        if let limit = options.limit { entities = Array(entities.prefix(limit)) }
        if options.includeHierarchy { entities = try entities.map { try withHierarchy($0, table: table) } }
        return entities
    }

    func withHierarchy(_ postcode: PostcodeResult) throws -> PostcodeResult {
        var hierarchy: [String: Entity?] = [:]
        if let municipalUnitID = postcode.municipalUnitID {
            hierarchy["municipalUnit"] = try loadEntity(table: .municipalUnits, id: municipalUnitID, includeOfficialCode: true)
        } else { hierarchy["municipalUnit"] = nil }
        if let communityID = postcode.communityID {
            hierarchy["community"] = try loadEntity(table: .communities, id: communityID, includeOfficialCode: true)
        } else { hierarchy["community"] = nil }
        if let municipalityID = postcode.municipalityID {
            hierarchy["municipality"] = try loadEntity(table: .municipalities, id: municipalityID, includeOfficialCode: true)
            if let municipality = hierarchy["municipality"] ?? nil { hierarchy.merge(try hierarchyForMunicipality(municipality.id)) { _, newest in newest } }
        } else {
            hierarchy["municipality"] = nil; hierarchy["regionalUnit"] = nil; hierarchy["region"] = nil; hierarchy["decentralizedAdministration"] = nil
        }
        return .init(postcode: postcode.postcode, latitude: postcode.latitude, longitude: postcode.longitude, localArea: postcode.localArea, municipalUnitID: postcode.municipalUnitID, communityID: postcode.communityID, municipalityID: postcode.municipalityID, hierarchy: hierarchy, streets: postcode.streets)
    }

    func withHierarchy(_ entity: Entity, table: Table) throws -> Entity {
        let hierarchy: [String: Entity?]
        switch table {
        case .regions:
            let administrationID = try scalarInt("SELECT decentralized_administration_id FROM regions WHERE id = ?", entity.id)
            hierarchy = ["decentralizedAdministration": try loadNamed(table: "decentralized_administrations", id: administrationID)]
        case .regionalUnits: hierarchy = try hierarchyForRegionalUnit(entity.id)
        case .municipalities: hierarchy = try hierarchyForMunicipality(entity.id)
        case .municipalUnits, .communities:
            let municipalityID = try scalarInt("SELECT municipality_id FROM \(table.rawValue) WHERE id = ?", entity.id)
            var ancestors = try hierarchyForMunicipality(municipalityID)
            ancestors["municipality"] = try loadEntity(table: .municipalities, id: municipalityID, includeOfficialCode: true)
            hierarchy = ancestors
        }
        return .init(id: entity.id, name: entity.name, officialCode: entity.officialCode, hierarchy: hierarchy)
    }

    func hierarchyForMunicipality(_ municipalityID: Int64) throws -> [String: Entity?] {
        let regionalUnitID = try scalarInt("SELECT regional_unit_id FROM municipalities WHERE id = ?", municipalityID)
        var hierarchy = try hierarchyForRegionalUnit(regionalUnitID)
        hierarchy["regionalUnit"] = try loadEntity(table: .regionalUnits, id: regionalUnitID, includeOfficialCode: true)
        return hierarchy
    }
    func hierarchyForRegionalUnit(_ regionalUnitID: Int64) throws -> [String: Entity?] {
        let regionID = try scalarInt("SELECT region_id FROM regional_units WHERE id = ?", regionalUnitID)
        let administrationID = try scalarInt("SELECT decentralized_administration_id FROM regions WHERE id = ?", regionID)
        return ["region": try loadEntity(table: .regions, id: regionID, includeOfficialCode: false), "decentralizedAdministration": try loadNamed(table: "decentralized_administrations", id: administrationID)]
    }

    func validateReference(_ reference: LocalityReference, table: Table, linked: Entity?) throws -> ValidationResult {
        let matches: [Entity]
        switch reference {
        case .id(let id): matches = (try loadEntity(table: table, id: id, includeOfficialCode: table.supportsOfficialCode)).map { [$0] } ?? []
        case .name(let name):
            guard !normalize(name).isEmpty else { return .init(status: .invalid, input: .locality(reference), matches: .entities([]), reason: "reference_must_not_be_empty") }
            matches = try list(table: table, parentID: nil, options: .init(includeOfficialCode: table.supportsOfficialCode)).filter { normalize($0.name).hasPrefix(normalize(name)) }
        }
        let valid = matches.contains { $0.id == linked?.id }
        return .init(status: valid ? .valid : .invalid, input: .locality(reference), matches: .entities(matches), reason: linked == nil ? "postcode_has_no_linked_entity" : nil)
    }
    func validateStreet(_ name: String, streets: [Street]) -> ValidationResult {
        let matches = streets.filter { normalize($0.name) == normalize(name) }
        return .init(status: matches.isEmpty ? .invalid : .valid, input: .text(name), matches: .streets(matches), reason: matches.isEmpty ? "street_not_found_for_postcode" : nil)
    }
    func streetMatches(_ result: ValidationResult?) -> [Street] {
        guard case .streets(let streets)? = result?.matches else { return [] }; return streets
    }
    func notEvaluated(_ input: ValidationInput, _ reason: String) -> ValidationResult { .init(status: .notEvaluated, input: input, matches: nil, reason: reason) }

    func streets(for postcode: String) throws -> [Street] {
        try query("SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id", [.text(postcode)]).map { row in
            .init(id: row.integer(0), postcode: row.text(1)!, name: row.text(2)!, oddStart: row.text(3), oddEnd: row.text(4), evenStart: row.text(5), evenEnd: row.text(6))
        }
    }
    func loadEntity(table: Table, id: Int64, includeOfficialCode: Bool) throws -> Entity? {
        let code = includeOfficialCode && table.supportsOfficialCode
        let rows = try query("SELECT id, name\(code ? ", official_code" : "") FROM \(table.rawValue) WHERE id = ?", [.integer(id)])
        return rows.first.map { entity(from: $0, hasOfficialCode: code) }
    }
    func loadNamed(table: String, id: Int64) throws -> Entity? {
        try query("SELECT id, name FROM \(table) WHERE id = ?", [.integer(id)]).first.map { entity(from: $0, hasOfficialCode: false) }
    }
    func scalarInt(_ sql: String, _ value: Int64) throws -> Int64 {
        guard let row = try query(sql, [.integer(value)]).first else { throw PostalCodeClientError.database("Expected a linked hierarchy row.") }
        return row.integer(0)
    }
    func entity(from row: Row, hasOfficialCode: Bool) -> Entity { .init(id: row.integer(0), name: row.text(1)!, officialCode: hasOfficialCode ? row.text(2) : nil) }
    func decodePostcode(from row: Row) -> PostcodeResult { .init(postcode: row.text(0)!, latitude: row.double(1), longitude: row.double(2), localArea: row.text(3), municipalUnitID: row.optionalInteger(4), communityID: row.optionalInteger(5), municipalityID: row.optionalInteger(6), hierarchy: nil, streets: nil) }
    func checkLimit(_ limit: Int?) throws { if let limit, limit <= 0 { throw PostalCodeClientError.invalidLimit } }

    struct Row { let values: [SQLiteValue]; func text(_ index: Int) -> String? { if case .text(let value) = values[index] { return value }; return nil }; func integer(_ index: Int) -> Int64 { if case .integer(let value) = values[index] { return value }; return 0 }; func optionalInteger(_ index: Int) -> Int64? { if case .integer(let value) = values[index] { return value }; return nil }; func double(_ index: Int) -> Double? { if case .double(let value) = values[index] { return value }; if case .integer(let value) = values[index] { return Double(value) }; return nil } }
    enum SQLiteValue { case null, integer(Int64), double(Double), text(String) }
    func query(_ sql: String, _ values: [Value] = []) throws -> [Row] {
        guard let database else { throw PostalCodeClientError.closed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError(database) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1); let result: Int32
            switch value { case .integer(let number): result = sqlite3_bind_int64(statement, index, number); case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, sqliteTransient) }
            guard result == SQLITE_OK else { throw databaseError(database) }
        }
        var result: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [SQLiteValue] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: values.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: values.append(.double(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT: values.append(.text(String(cString: sqlite3_column_text(statement, column))))
                default: values.append(.null)
                }
            }
            result.append(.init(values: values))
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else { throw databaseError(database) }
        return result
    }
    func databaseError(_ database: OpaquePointer) -> PostalCodeClientError { .database(String(cString: sqlite3_errmsg(database))) }
}

private extension String {
    var isFiveDigits: Bool { count == 5 && allSatisfy { $0.isNumber } && unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 } }
}

private func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "el_GR"))
        .unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil }
        .map(String.init).joined().replacingOccurrences(of: "ς", with: "σ")
}

private extension Street {
    /// nil means this street has no usable range for the requested parity.
    func contains(number: Int) -> Bool? {
        let startText = number.isMultiple(of: 2) ? evenStart : oddStart
        let endText = number.isMultiple(of: 2) ? evenEnd : oddEnd
        guard let start = startText.flatMap(rangeNumber) else { return nil }
        if normalize(endText ?? "") == "τελ" { return number >= start }
        guard let end = endText.flatMap(rangeNumber) else { return nil }
        return number >= start && number <= end
    }
}

private func rangeNumber(_ value: String) -> Int? {
    let digits = value.prefix { $0.isNumber }
    return digits.isEmpty ? nil : Int(digits)
}
