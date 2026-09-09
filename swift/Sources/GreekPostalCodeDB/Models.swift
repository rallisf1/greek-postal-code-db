import Foundation

/// An administrative entity in the Greek postal-code hierarchy.
public struct Entity: Sendable, Equatable {
    public let id: Int64
    public let name: String
    /// Present only when requested and available in the source data.
    public let officialCode: String?
    /// Ancestors, keyed by `region`, `regionalUnit`, `municipality`, or
    /// `decentralizedAdministration` as appropriate for the entity type.
    public let hierarchy: [String: Entity?]?

    public init(id: Int64, name: String, officialCode: String? = nil, hierarchy: [String: Entity?]? = nil) {
        self.id = id
        self.name = name
        self.officialCode = officialCode
        self.hierarchy = hierarchy
    }
}

public struct Street: Sendable, Equatable {
    public let id: Int64
    public let postcode: String
    public let name: String
    public let oddStart: String?
    public let oddEnd: String?
    public let evenStart: String?
    public let evenEnd: String?
}

public struct PostcodeInclude: Sendable, Equatable {
    public var hierarchy: Bool
    public var streets: Bool

    public init(hierarchy: Bool = false, streets: Bool = false) {
        self.hierarchy = hierarchy
        self.streets = streets
    }
}

public struct PostcodeResult: Sendable, Equatable {
    public let postcode: String
    public let latitude: Double?
    public let longitude: Double?
    public let localArea: String?
    public let municipalUnitID: Int64?
    public let communityID: Int64?
    public let municipalityID: Int64?
    public let hierarchy: [String: Entity?]?
    public let streets: [Street]?
}

/// Common options for the five list and search APIs. A nil limit returns all
/// results; a supplied limit must be positive.
public struct EntityOptions: Sendable, Equatable {
    public var limit: Int?
    public var includeOfficialCode: Bool
    public var includeHierarchy: Bool

    public init(limit: Int? = nil, includeOfficialCode: Bool = false, includeHierarchy: Bool = false) {
        self.limit = limit
        self.includeOfficialCode = includeOfficialCode
        self.includeHierarchy = includeHierarchy
    }
}

public enum LocalityReference: Sendable, Equatable {
    case id(Int64)
    case name(String)
}

public struct AddressInput: Sendable, Equatable {
    public var postcode: String
    public var street: String?
    public var houseNumber: Int?
    public var municipality: LocalityReference?
    public var municipalUnit: LocalityReference?
    public var community: LocalityReference?
    public var regionalUnit: LocalityReference?
    public var region: LocalityReference?

    public init(
        postcode: String,
        street: String? = nil,
        houseNumber: Int? = nil,
        municipality: LocalityReference? = nil,
        municipalUnit: LocalityReference? = nil,
        community: LocalityReference? = nil,
        regionalUnit: LocalityReference? = nil,
        region: LocalityReference? = nil
    ) {
        self.postcode = postcode
        self.street = street
        self.houseNumber = houseNumber
        self.municipality = municipality
        self.municipalUnit = municipalUnit
        self.community = community
        self.regionalUnit = regionalUnit
        self.region = region
    }
}

public enum ValidationStatus: String, Sendable, Equatable {
    case valid
    case invalid
    case notEvaluated = "not_evaluated"
}

public enum ValidationInput: Sendable, Equatable {
    case text(String)
    case integer(Int)
    case locality(LocalityReference)
}

public enum ValidationMatches: Sendable, Equatable {
    case postcodes([PostcodeResult])
    case streets([Street])
    case entities([Entity])
}

/// The outcome for one independently evaluated input component.
public struct ValidationResult: Sendable, Equatable {
    public let status: ValidationStatus
    public let input: ValidationInput
    public let matches: ValidationMatches?
    public let reason: String?
}

/// Per-component address validation. There is intentionally no aggregate
/// boolean: callers can decide which components matter for their use case.
public struct AddressValidation: Sendable, Equatable {
    public let postcode: ValidationResult
    public let street: ValidationResult?
    public let houseNumber: ValidationResult?
    public let municipality: ValidationResult?
    public let municipalUnit: ValidationResult?
    public let community: ValidationResult?
    public let regionalUnit: ValidationResult?
    public let region: ValidationResult?
}

public enum PostalCodeClientError: Error, LocalizedError, Equatable {
    case closed
    case invalidLimit
    case database(String)
    case bundledDatabaseUnavailable

    public var errorDescription: String? {
        switch self {
        case .closed: "The postal code client is closed."
        case .invalidLimit: "limit must be a positive integer when supplied."
        case .database(let message): message
        case .bundledDatabaseUnavailable: "The bundled library.sqlite database is unavailable."
        }
    }
}
