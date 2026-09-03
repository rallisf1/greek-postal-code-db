using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;

namespace GreekPostalCodeDb;

/// <summary>An offline, read-only client for the bundled Greek postal-code database.</summary>
public sealed class PostalCodeClient : IDisposable
{
    private static readonly Regex PostcodePattern = new("^\\d{5}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex RangeNumberPattern = new("^\\s*(\\d+)", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private SqliteConnection? _connection;
    private readonly string _databasePath;

    private PostalCodeClient(string databasePath, SqliteConnection connection) => (_databasePath, _connection) = (databasePath, connection);

    /// <summary>Opens the database embedded in this package in read-only mode.</summary>
    public static PostalCodeClient Create()
    {
        var path = Path.Combine(Path.GetTempPath(), $"greek-postal-code-db-{Guid.NewGuid():N}.sqlite");
        try
        {
            using var source = typeof(PostalCodeClient).Assembly.GetManifestResourceStream("GreekPostalCodeDb.library.sqlite")
                ?? throw new InvalidOperationException("The bundled library.sqlite resource is missing.");
            using (var target = File.Create(path)) source.CopyTo(target);
            var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadOnly }.ToString());
            connection.Open();
            using var command = connection.CreateCommand();
            command.CommandText = "PRAGMA query_only = ON;";
            command.ExecuteNonQuery();
            return new PostalCodeClient(path, connection);
        }
        catch
        {
            File.Delete(path);
            throw;
        }
    }

    public void Dispose()
    {
        _connection?.Dispose();
        _connection = null;
        try { File.Delete(_databasePath); } catch (IOException) { }
        GC.SuppressFinalize(this);
    }

    public IReadOnlyList<Entity> ListRegions(ListOptions? options = null) => List("regions", null, null, options ?? new(), false);
    public IReadOnlyList<Entity> ListRegionalUnits(RegionalUnitOptions? options = null) => List("regional_units", "region_id", options?.RegionId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> ListMunicipalities(MunicipalityOptions? options = null) => List("municipalities", "regional_unit_id", options?.RegionalUnitId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> ListMunicipalUnits(MunicipalityChildOptions? options = null) => List("municipal_units", "municipality_id", options?.MunicipalityId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> ListCommunities(MunicipalityChildOptions? options = null) => List("communities", "municipality_id", options?.MunicipalityId, options ?? new(), options?.IncludeOfficialCode ?? false);

    public IReadOnlyList<Entity> SearchRegions(string query, ListOptions? options = null) => Search("regions", null, query, null, options ?? new(), false);
    public IReadOnlyList<Entity> SearchRegionalUnits(string query, RegionalUnitOptions? options = null) => Search("regional_units", "region_id", query, options?.RegionId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> SearchMunicipalities(string query, MunicipalityOptions? options = null) => Search("municipalities", "regional_unit_id", query, options?.RegionalUnitId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> SearchMunicipalUnits(string query, MunicipalityChildOptions? options = null) => Search("municipal_units", "municipality_id", query, options?.MunicipalityId, options ?? new(), options?.IncludeOfficialCode ?? false);
    public IReadOnlyList<Entity> SearchCommunities(string query, MunicipalityChildOptions? options = null) => Search("communities", "municipality_id", query, options?.MunicipalityId, options ?? new(), options?.IncludeOfficialCode ?? false);

    public PostcodeResult? GetPostcode(string postcode, PostcodeOptions? options = null)
    {
        if (!PostcodePattern.IsMatch(postcode)) return null;
        options ??= new();
        var result = One("SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = $postcode", command => command.Parameters.AddWithValue("$postcode", postcode), Location);
        if (result is null) return null;
        return result with
        {
            Hierarchy = options.IncludeHierarchy ? PostcodeHierarchy(result) : null,
            Streets = options.IncludeStreets ? Streets(postcode) : null,
        };
    }

    public AddressValidation ValidateAddress(AddressInput input)
    {
        var postcode = GetPostcode(input.Postcode, new(true, input.Street is not null || input.HouseNumber is not null));
        var postcodeResult = !PostcodePattern.IsMatch(input.Postcode)
            ? Invalid(input.Postcode, "postcode_must_be_exactly_five_digits")
            : postcode is null ? Invalid(input.Postcode, "postcode_not_found") : Valid(input.Postcode, [postcode]);
        if (postcode is null)
            return new(postcodeResult,
                input.Street is null ? null : NotEvaluated(input.Street, "postcode_not_found"),
                input.HouseNumber is null ? null : NotEvaluated(input.HouseNumber, "postcode_not_found"),
                input.Municipality is null ? null : NotEvaluated(input.Municipality, "postcode_not_found"),
                input.MunicipalUnit is null ? null : NotEvaluated(input.MunicipalUnit, "postcode_not_found"),
                input.Community is null ? null : NotEvaluated(input.Community, "postcode_not_found"),
                input.RegionalUnit is null ? null : NotEvaluated(input.RegionalUnit, "postcode_not_found"),
                input.Region is null ? null : NotEvaluated(input.Region, "postcode_not_found"));

        var hierarchy = postcode.Hierarchy!;
        var street = input.Street is null ? null : ValidateStreet(input.Street, postcode.Streets!);
        var houseNumber = input.HouseNumber is null ? null : ValidateHouseNumber(input.HouseNumber, street);
        return new(postcodeResult, street, houseNumber,
            input.Municipality is null ? null : ValidateReference("municipalities", input.Municipality, hierarchy.Municipality),
            input.MunicipalUnit is null ? null : ValidateReference("municipal_units", input.MunicipalUnit, hierarchy.MunicipalUnit),
            input.Community is null ? null : ValidateReference("communities", input.Community, hierarchy.Community),
            input.RegionalUnit is null ? null : ValidateReference("regional_units", input.RegionalUnit, hierarchy.RegionalUnit),
            input.Region is null ? null : ValidateReference("regions", input.Region, hierarchy.Region));
    }

    private IReadOnlyList<Entity> List(string table, string? parentColumn, long? parentId, ListOptions options, bool officialCode)
    {
        ValidateLimit(options.Limit);
        var sql = $"SELECT id, name{(officialCode ? ", official_code" : "")} FROM {table}" + (parentColumn is not null && parentId is not null ? $" WHERE {parentColumn} = $parent" : "") + " ORDER BY name, id";
        var entities = All(sql, command => { if (parentColumn is not null && parentId is not null) command.Parameters.AddWithValue("$parent", parentId.Value); }, row => Entity(row, officialCode));
        var withHierarchy = options.IncludeHierarchy ? entities.Select(entity => entity with { Hierarchy = EntityHierarchy(table, entity.Id) }) : entities;
        return options.Limit is int limit ? withHierarchy.Take(limit).ToArray() : withHierarchy.ToArray();
    }

    private IReadOnlyList<Entity> Search(string table, string? parentColumn, string query, long? parentId, ListOptions options, bool officialCode)
    {
        var normalized = Normalize(query);
        if (normalized.Length == 0) return [];
        var matches = List(table, parentColumn, parentId, options with { IncludeHierarchy = false, Limit = null }, officialCode)
            .Where(entity => Normalize(entity.Name).StartsWith(normalized, StringComparison.Ordinal))
            .Select(entity => options.IncludeHierarchy ? entity with { Hierarchy = EntityHierarchy(table, entity.Id) } : entity)
            .ToArray();
        return options.Limit is int limit ? matches.Take(limit).ToArray() : matches;
    }

    private EntityHierarchy EntityHierarchy(string table, long id) => table switch
    {
        "regions" => new(DecentralizedAdministration: Named(One("SELECT da.id, da.name FROM regions r JOIN decentralized_administrations da ON da.id = r.decentralized_administration_id WHERE r.id = $id", c => c.Parameters.AddWithValue("$id", id), row => Entity(row, false)))),
        "regional_units" => RegionalUnitHierarchy(id),
        "municipalities" => MunicipalityHierarchy(id),
        _ => MunicipalityChildHierarchy(ScalarLong($"SELECT municipality_id FROM {table} WHERE id = $id", id)),
    };

    private EntityHierarchy PostcodeHierarchy(PostcodeResult location)
    {
        var municipalUnit = location.MunicipalUnitId is long unitId ? Coded(One("SELECT id, name, official_code FROM municipal_units WHERE id = $id", c => c.Parameters.AddWithValue("$id", unitId), row => Entity(row, true))) : null;
        var community = location.CommunityId is long communityId ? Coded(One("SELECT id, name, official_code FROM communities WHERE id = $id", c => c.Parameters.AddWithValue("$id", communityId), row => Entity(row, true))) : null;
        var municipality = location.MunicipalityId is long municipalityId ? Coded(One("SELECT id, name, official_code FROM municipalities WHERE id = $id", c => c.Parameters.AddWithValue("$id", municipalityId), row => Entity(row, true))) : null;
        var parent = municipality is null ? new EntityHierarchy() : MunicipalityHierarchy(municipality.Id);
        return parent with { Municipality = municipality, MunicipalUnit = municipalUnit, Community = community };
    }

    private EntityHierarchy RegionalUnitHierarchy(long id)
    {
        var region = Named(One("SELECT r.id, r.name FROM regional_units ru JOIN regions r ON r.id = ru.region_id WHERE ru.id = $id", c => c.Parameters.AddWithValue("$id", id), row => Entity(row, false)));
        var administration = Named(One("SELECT da.id, da.name FROM regional_units ru JOIN regions r ON r.id = ru.region_id JOIN decentralized_administrations da ON da.id = r.decentralized_administration_id WHERE ru.id = $id", c => c.Parameters.AddWithValue("$id", id), row => Entity(row, false)));
        return new(DecentralizedAdministration: administration, Region: region);
    }

    private EntityHierarchy MunicipalityHierarchy(long id)
    {
        var unit = Coded(One("SELECT ru.id, ru.name, ru.official_code FROM municipalities m JOIN regional_units ru ON ru.id = m.regional_unit_id WHERE m.id = $id", c => c.Parameters.AddWithValue("$id", id), row => Entity(row, true)));
        var parent = unit is null ? new EntityHierarchy() : RegionalUnitHierarchy(unit.Id);
        return parent with { RegionalUnit = unit };
    }

    private EntityHierarchy MunicipalityChildHierarchy(long? municipalityId)
    {
        if (municipalityId is null) return new();
        var municipality = Coded(One("SELECT id, name, official_code FROM municipalities WHERE id = $id", c => c.Parameters.AddWithValue("$id", municipalityId.Value), row => Entity(row, true)));
        var parent = municipality is null ? new EntityHierarchy() : MunicipalityHierarchy(municipality.Id);
        return parent with { Municipality = municipality };
    }

    private IReadOnlyList<Street> Streets(string postcode) => All("SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = $postcode ORDER BY name, id", c => c.Parameters.AddWithValue("$postcode", postcode), Street);

    private ValidationResult ValidateReference(string table, LocalityReference reference, Entity? linked)
    {
        if (reference.Id is null && string.IsNullOrWhiteSpace(reference.Name)) return Invalid(reference, "reference_must_not_be_empty", []);
        var officialCode = table != "regions";
        var matches = reference.Id is long id
            ? All($"SELECT id, name{(officialCode ? ", official_code" : "")} FROM {table} WHERE id = $id", c => c.Parameters.AddWithValue("$id", id), row => Entity(row, officialCode))
            : List(table, null, null, new(), officialCode).Where(entity => Normalize(entity.Name).StartsWith(Normalize(reference.Name!), StringComparison.Ordinal)).ToArray();
        var values = matches.Cast<object>().ToArray();
        if (linked is null) return Invalid(reference, "postcode_has_no_linked_entity", values);
        return matches.Any(candidate => candidate.Id == linked.Id) ? Valid(reference, values) : Invalid(reference, null, values);
    }

    private static ValidationResult ValidateStreet(string street, IReadOnlyList<Street> streets)
    {
        var matches = streets.Where(candidate => Normalize(candidate.Name) == Normalize(street)).Cast<object>().ToArray();
        return matches.Length > 0 ? Valid(street, matches) : Invalid(street, "street_not_found_for_postcode", matches);
    }

    private static ValidationResult ValidateHouseNumber(object value, ValidationResult? street)
    {
        if (street?.Status != ValidationStatus.Valid) return NotEvaluated(value, "street_is_required_and_must_be_valid");
        if (!PositiveInteger(value, out var number)) return Invalid(value, "house_number_must_be_a_positive_integer");
        var streets = street.Matches!.Cast<Street>().ToArray();
        var checks = streets.Select(candidate => ContainsHouseNumber(candidate, number)).Where(check => check is not null).Cast<bool>().ToArray();
        return checks.Length == 0 || checks.Any(check => check) ? Valid(value, streets.Cast<object>().ToArray(), checks.Length == 0 ? "street_has_no_usable_range" : null) : Invalid(value, null, streets.Cast<object>().ToArray());
    }

    private static bool? ContainsHouseNumber(Street street, long number)
    {
        var start = number % 2 == 0 ? street.EvenStart : street.OddStart;
        var end = number % 2 == 0 ? street.EvenEnd : street.OddEnd;
        if (!RangeNumber(start, out var first)) return null;
        if (Normalize(end ?? "") == "τελ") return number >= first;
        return RangeNumber(end, out var last) ? number >= first && number <= last : null;
    }

    private static bool PositiveInteger(object value, out long number) => value switch
    {
        byte n => Set(n, out number), short n when n > 0 => Set(n, out number), int n when n > 0 => Set(n, out number), long n when n > 0 => Set(n, out number),
        string text when long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var n) && n > 0 => Set(n, out number),
        _ => Set(0, out number, false),
    };
    private static bool Set(long value, out long output, bool valid = true) { output = value; return valid; }
    private static bool RangeNumber(string? value, out long number) => long.TryParse(RangeNumberPattern.Match(value ?? "").Groups[1].Value, out number);
    private static string Normalize(string value) => string.Concat(value.Normalize(NormalizationForm.FormD).ToLowerInvariant().Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark && char.IsLetterOrDigit(character)));
    private static void ValidateLimit(int? limit) { if (limit is <= 0) throw new ArgumentOutOfRangeException(nameof(limit), "Limit must be a positive integer."); }
    private static Entity Entity(SqliteDataReader row, bool officialCode) => new(row.GetInt64(0), row.GetString(1), officialCode && !row.IsDBNull(2) ? row.GetString(2) : null);
    private static Entity? Named(Entity? entity) => entity is null ? null : entity with { OfficialCode = null };
    private static Entity? Coded(Entity? entity) => entity;
    private static Street Street(SqliteDataReader row) => new(row.GetInt64(0), row.GetString(1), row.GetString(2), Text(row, 3), Text(row, 4), Text(row, 5), Text(row, 6));
    private static PostcodeResult Location(SqliteDataReader row) => new(row.GetString(0), Number(row, 1), Number(row, 2), Text(row, 3), Integer(row, 4), Integer(row, 5), Integer(row, 6));
    private static string? Text(SqliteDataReader row, int index) => row.IsDBNull(index) ? null : row.GetString(index);
    private static double? Number(SqliteDataReader row, int index) => row.IsDBNull(index) ? null : row.GetDouble(index);
    private static long? Integer(SqliteDataReader row, int index) => row.IsDBNull(index) ? null : row.GetInt64(index);
    private static ValidationResult Valid(object input, IReadOnlyList<object> matches, string? reason = null) => new(ValidationStatus.Valid, input, matches, reason);
    private static ValidationResult Invalid(object input, string? reason, IReadOnlyList<object>? matches = null) => new(ValidationStatus.Invalid, input, matches, reason);
    private static ValidationResult NotEvaluated(object input, string reason) => new(ValidationStatus.NotEvaluated, input, null, reason);
    private long? ScalarLong(string sql, long id) => One(sql, c => c.Parameters.AddWithValue("$id", id), row => row.GetInt64(0));
    private T? One<T>(string sql, Action<SqliteCommand> parameters, Func<SqliteDataReader, T> map) where T : class { using var command = Command(sql, parameters); using var reader = command.ExecuteReader(); return reader.Read() ? map(reader) : null; }
    private long? One(string sql, Action<SqliteCommand> parameters, Func<SqliteDataReader, long> map) { using var command = Command(sql, parameters); using var reader = command.ExecuteReader(); return reader.Read() ? map(reader) : null; }
    private IReadOnlyList<T> All<T>(string sql, Action<SqliteCommand> parameters, Func<SqliteDataReader, T> map) { using var command = Command(sql, parameters); using var reader = command.ExecuteReader(); var result = new List<T>(); while (reader.Read()) result.Add(map(reader)); return result; }
    private SqliteCommand Command(string sql, Action<SqliteCommand> parameters) { var command = Connection.CreateCommand(); command.CommandText = sql; parameters(command); return command; }
    private SqliteConnection Connection => _connection ?? throw new ObjectDisposedException(nameof(PostalCodeClient));
}
