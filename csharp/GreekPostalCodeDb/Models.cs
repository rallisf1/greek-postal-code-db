namespace GreekPostalCodeDb;

public sealed record Entity(long Id, string Name, string? OfficialCode = null, EntityHierarchy? Hierarchy = null);

public sealed record EntityHierarchy(
    Entity? DecentralizedAdministration = null,
    Entity? Region = null,
    Entity? RegionalUnit = null,
    Entity? Municipality = null,
    Entity? MunicipalUnit = null,
    Entity? Community = null);

public sealed record Street(
    long Id,
    string Postcode,
    string Name,
    string? OddStart,
    string? OddEnd,
    string? EvenStart,
    string? EvenEnd);

public sealed record PostcodeResult(
    string Postcode,
    double? Latitude,
    double? Longitude,
    string? LocalArea,
    long? MunicipalUnitId,
    long? CommunityId,
    long? MunicipalityId,
    EntityHierarchy? Hierarchy = null,
    IReadOnlyList<Street>? Streets = null);

public record ListOptions(int? Limit = null, bool IncludeHierarchy = false, bool IncludeOfficialCode = false);
public sealed record RegionalUnitOptions(long? RegionId = null, int? Limit = null, bool IncludeHierarchy = false, bool IncludeOfficialCode = false)
    : ListOptions(Limit, IncludeHierarchy, IncludeOfficialCode);
public sealed record MunicipalityOptions(long? RegionalUnitId = null, int? Limit = null, bool IncludeHierarchy = false, bool IncludeOfficialCode = false)
    : ListOptions(Limit, IncludeHierarchy, IncludeOfficialCode);
public sealed record MunicipalityChildOptions(long? MunicipalityId = null, int? Limit = null, bool IncludeHierarchy = false, bool IncludeOfficialCode = false)
    : ListOptions(Limit, IncludeHierarchy, IncludeOfficialCode);
public sealed record PostcodeOptions(bool IncludeHierarchy = false, bool IncludeStreets = false);

/// <summary>Identifies a locality by its source ID or normalized name prefix.</summary>
public sealed record LocalityReference
{
    private LocalityReference(long? id, string? name) => (Id, Name) = (id, name);
    public long? Id { get; }
    public string? Name { get; }
    public static LocalityReference ById(long id) => new(id, null);
    public static LocalityReference ByName(string name) => new(null, name);
    public static implicit operator LocalityReference(long id) => ById(id);
    public static implicit operator LocalityReference(string name) => ByName(name);
}

public sealed record AddressInput(
    string Postcode,
    string? Street = null,
    object? HouseNumber = null,
    LocalityReference? Municipality = null,
    LocalityReference? MunicipalUnit = null,
    LocalityReference? Community = null,
    LocalityReference? RegionalUnit = null,
    LocalityReference? Region = null);

public enum ValidationStatus { Valid, Invalid, NotEvaluated }

public sealed record ValidationResult(
    ValidationStatus Status,
    object? Input,
    IReadOnlyList<object>? Matches = null,
    string? Reason = null);

/// <summary>Independent results for the address components supplied by the caller.</summary>
public sealed record AddressValidation(
    ValidationResult Postcode,
    ValidationResult? Street = null,
    ValidationResult? HouseNumber = null,
    ValidationResult? Municipality = null,
    ValidationResult? MunicipalUnit = null,
    ValidationResult? Community = null,
    ValidationResult? RegionalUnit = null,
    ValidationResult? Region = null);
