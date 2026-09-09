package io.github.rallisf1.greekpostalcode;

import static io.github.rallisf1.greekpostalcode.Models.*;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.*;
import java.text.Normalizer;
import java.util.*;
import java.util.regex.Pattern;

/** Offline, read-only access to the Greek Postal Code DB bundled in this JAR. */
public final class PostalCodeClient implements AutoCloseable {
    private static final Pattern POSTCODE = Pattern.compile("\\d{5}");
    private static final Pattern RANGE_NUMBER = Pattern.compile("^\\s*(\\d+)");
    private Connection connection;
    private final Path databasePath;

    private PostalCodeClient(Connection connection, Path databasePath) { this.connection = connection; this.databasePath = databasePath; }

    /** Opens a temporary read-only copy of the SQLite database embedded in this JAR. */
    public static PostalCodeClient create() {
        Path path = null;
        try (InputStream input = PostalCodeClient.class.getResourceAsStream("/library.sqlite")) {
            if (input == null) throw new IllegalStateException("The bundled library.sqlite resource is missing.");
            path = Files.createTempFile("greek-postal-code-db-", ".sqlite");
            Files.copy(input, path, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            Connection connection = DriverManager.getConnection("jdbc:sqlite:file:" + path.toAbsolutePath() + "?mode=ro");
            try (Statement statement = connection.createStatement()) { statement.execute("PRAGMA query_only = ON"); }
            return new PostalCodeClient(connection, path);
        } catch (SQLException | IOException exception) {
            if (path != null) try { Files.deleteIfExists(path); } catch (IOException ignored) { }
            throw new PostalCodeException("Could not open the bundled SQLite database.", exception);
        }
    }

    @Override public void close() {
        if (connection == null) return;
        try { connection.close(); } catch (SQLException exception) { throw new PostalCodeException("Could not close the SQLite database.", exception); }
        finally { connection = null; try { Files.deleteIfExists(databasePath); } catch (IOException ignored) { } }
    }

    public List<Entity> listRegions(ListOptions options) { return list("regions", null, null, defaults(options), false); }
    public List<Entity> listRegions() { return listRegions(new ListOptions()); }
    public List<Entity> listRegionalUnits(RegionalUnitOptions options) { options = options == null ? new RegionalUnitOptions() : options; return list("regional_units", "region_id", options.regionId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> listMunicipalities(MunicipalityOptions options) { options = options == null ? new MunicipalityOptions() : options; return list("municipalities", "regional_unit_id", options.regionalUnitId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> listMunicipalUnits(MunicipalityChildOptions options) { options = options == null ? new MunicipalityChildOptions() : options; return list("municipal_units", "municipality_id", options.municipalityId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> listCommunities(MunicipalityChildOptions options) { options = options == null ? new MunicipalityChildOptions() : options; return list("communities", "municipality_id", options.municipalityId(), options.listOptions(), options.includeOfficialCode()); }

    public List<Entity> searchRegions(String query, ListOptions options) { return search("regions", null, query, null, defaults(options), false); }
    public List<Entity> searchRegions(String query) { return searchRegions(query, new ListOptions()); }
    public List<Entity> searchRegionalUnits(String query, RegionalUnitOptions options) { options = options == null ? new RegionalUnitOptions() : options; return search("regional_units", "region_id", query, options.regionId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> searchMunicipalities(String query, MunicipalityOptions options) { options = options == null ? new MunicipalityOptions() : options; return search("municipalities", "regional_unit_id", query, options.regionalUnitId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> searchMunicipalUnits(String query, MunicipalityChildOptions options) { options = options == null ? new MunicipalityChildOptions() : options; return search("municipal_units", "municipality_id", query, options.municipalityId(), options.listOptions(), options.includeOfficialCode()); }
    public List<Entity> searchCommunities(String query, MunicipalityChildOptions options) { options = options == null ? new MunicipalityChildOptions() : options; return search("communities", "municipality_id", query, options.municipalityId(), options.listOptions(), options.includeOfficialCode()); }

    public PostcodeResult getPostcode(String postcode, PostcodeOptions options) {
        if (postcode == null || !POSTCODE.matcher(postcode).matches()) return null;
        options = options == null ? new PostcodeOptions() : options;
        PostcodeResult location = one("SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?", statement -> statement.setString(1, postcode), this::location);
        if (location == null) return null;
        return new PostcodeResult(location.postcode(), location.latitude(), location.longitude(), location.localArea(), location.municipalUnitId(), location.communityId(), location.municipalityId(), options.includeHierarchy() ? postcodeHierarchy(location) : null, options.includeStreets() ? streets(postcode) : null);
    }
    public PostcodeResult getPostcode(String postcode) { return getPostcode(postcode, new PostcodeOptions()); }

    public AddressValidation validateAddress(AddressInput input) {
        Objects.requireNonNull(input, "input");
        PostcodeResult postcode = getPostcode(input.postcode(), new PostcodeOptions(true, input.street() != null || input.houseNumber() != null));
        ValidationResult postcodeResult = input.postcode() == null || !POSTCODE.matcher(input.postcode()).matches() ? invalid(input.postcode(), "postcode_must_be_exactly_five_digits", null) : postcode == null ? invalid(input.postcode(), "postcode_not_found", null) : valid(input.postcode(), List.of(postcode), null);
        if (postcode == null) return new AddressValidation(postcodeResult, ne(input.street(), "postcode_not_found"), ne(input.houseNumber(), "postcode_not_found"), ne(input.municipality(), "postcode_not_found"), ne(input.municipalUnit(), "postcode_not_found"), ne(input.community(), "postcode_not_found"), ne(input.regionalUnit(), "postcode_not_found"), ne(input.region(), "postcode_not_found"));
        EntityHierarchy hierarchy = postcode.hierarchy();
        ValidationResult street = input.street() == null ? null : validateStreet(input.street(), postcode.streets());
        return new AddressValidation(postcodeResult, street, input.houseNumber() == null ? null : validateHouseNumber(input.houseNumber(), street),
            input.municipality() == null ? null : validateReference("municipalities", input.municipality(), hierarchy.municipality()),
            input.municipalUnit() == null ? null : validateReference("municipal_units", input.municipalUnit(), hierarchy.municipalUnit()),
            input.community() == null ? null : validateReference("communities", input.community(), hierarchy.community()),
            input.regionalUnit() == null ? null : validateReference("regional_units", input.regionalUnit(), hierarchy.regionalUnit()),
            input.region() == null ? null : validateReference("regions", input.region(), hierarchy.region()));
    }

    private List<Entity> list(String table, String parentColumn, Long parentId, ListOptions options, boolean officialCode) {
        limit(options.limit());
        String sql = "SELECT id, name" + (officialCode ? ", official_code" : "") + " FROM " + table + (parentColumn != null && parentId != null ? " WHERE " + parentColumn + " = ?" : "") + " ORDER BY name, id";
        List<Entity> result = all(sql, statement -> { if (parentColumn != null && parentId != null) statement.setLong(1, parentId); }, row -> entity(row, officialCode));
        if (options.includeHierarchy()) result = result.stream().map(value -> new Entity(value.id(), value.name(), value.officialCode(), entityHierarchy(table, value.id()))).toList();
        return options.limit() == null ? result : result.subList(0, Math.min(options.limit(), result.size()));
    }
    private List<Entity> search(String table, String parentColumn, String query, Long parentId, ListOptions options, boolean officialCode) {
        String normalized = normalize(query);
        if (normalized.isEmpty()) return List.of();
        List<Entity> matches = list(table, parentColumn, parentId, new ListOptions(null, options.includeHierarchy(), options.includeOfficialCode()), officialCode).stream().filter(value -> normalize(value.name()).startsWith(normalized)).toList();
        return options.limit() == null ? matches : matches.subList(0, Math.min(options.limit(), matches.size()));
    }
    private EntityHierarchy entityHierarchy(String table, long id) {
        return switch (table) {
            case "regions" -> new EntityHierarchy(named(one("SELECT da.id, da.name FROM regions r JOIN decentralized_administrations da ON da.id = r.decentralized_administration_id WHERE r.id = ?", s -> s.setLong(1, id), row -> entity(row, false))), null, null, null, null, null);
            case "regional_units" -> regionalUnitHierarchy(id);
            case "municipalities" -> municipalityHierarchy(id);
            default -> municipalityChildHierarchy(one("SELECT municipality_id FROM " + table + " WHERE id = ?", s -> s.setLong(1, id), row -> row.getLong(1)));
        };
    }
    private EntityHierarchy postcodeHierarchy(PostcodeResult location) {
        Entity unit = location.municipalUnitId() == null ? null : coded(one("SELECT id, name, official_code FROM municipal_units WHERE id = ?", s -> s.setLong(1, location.municipalUnitId()), row -> entity(row, true)));
        Entity community = location.communityId() == null ? null : coded(one("SELECT id, name, official_code FROM communities WHERE id = ?", s -> s.setLong(1, location.communityId()), row -> entity(row, true)));
        Entity municipality = location.municipalityId() == null ? null : coded(one("SELECT id, name, official_code FROM municipalities WHERE id = ?", s -> s.setLong(1, location.municipalityId()), row -> entity(row, true)));
        EntityHierarchy parent = municipality == null ? emptyHierarchy() : municipalityHierarchy(municipality.id());
        return new EntityHierarchy(parent.decentralizedAdministration(), parent.region(), parent.regionalUnit(), municipality, unit, community);
    }
    private EntityHierarchy regionalUnitHierarchy(long id) {
        Entity region = named(one("SELECT r.id, r.name FROM regional_units ru JOIN regions r ON r.id = ru.region_id WHERE ru.id = ?", s -> s.setLong(1, id), row -> entity(row, false)));
        Entity administration = named(one("SELECT da.id, da.name FROM regional_units ru JOIN regions r ON r.id = ru.region_id JOIN decentralized_administrations da ON da.id = r.decentralized_administration_id WHERE ru.id = ?", s -> s.setLong(1, id), row -> entity(row, false)));
        return new EntityHierarchy(administration, region, null, null, null, null);
    }
    private EntityHierarchy municipalityHierarchy(long id) {
        Entity unit = coded(one("SELECT ru.id, ru.name, ru.official_code FROM municipalities m JOIN regional_units ru ON ru.id = m.regional_unit_id WHERE m.id = ?", s -> s.setLong(1, id), row -> entity(row, true)));
        EntityHierarchy parent = unit == null ? emptyHierarchy() : regionalUnitHierarchy(unit.id());
        return new EntityHierarchy(parent.decentralizedAdministration(), parent.region(), unit, null, null, null);
    }
    private EntityHierarchy municipalityChildHierarchy(Long id) {
        if (id == null) return emptyHierarchy();
        Entity municipality = coded(one("SELECT id, name, official_code FROM municipalities WHERE id = ?", s -> s.setLong(1, id), row -> entity(row, true)));
        EntityHierarchy parent = municipality == null ? emptyHierarchy() : municipalityHierarchy(municipality.id());
        return new EntityHierarchy(parent.decentralizedAdministration(), parent.region(), parent.regionalUnit(), municipality, null, null);
    }
    private List<Street> streets(String postcode) { return all("SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id", s -> s.setString(1, postcode), this::street); }
    private ValidationResult validateReference(String table, LocalityReference reference, Entity linked) {
        boolean officialCode = !table.equals("regions");
        List<Entity> matches;
        if (reference instanceof LocalityId id) matches = all("SELECT id, name" + (officialCode ? ", official_code" : "") + " FROM " + table + " WHERE id = ?", s -> s.setLong(1, id.id()), row -> entity(row, officialCode));
        else if (reference instanceof LocalityName name && !normalize(name.name()).isEmpty()) matches = list(table, null, null, new ListOptions(), officialCode).stream().filter(value -> normalize(value.name()).startsWith(normalize(name.name()))).toList();
        else return invalid(reference, "reference_must_not_be_empty", List.of());
        if (linked == null) return invalid(reference, "postcode_has_no_linked_entity", matches);
        return matches.stream().anyMatch(value -> value.id() == linked.id()) ? valid(reference, matches, null) : invalid(reference, null, matches);
    }
    private static ValidationResult validateStreet(String input, List<Street> streets) { List<Street> matches = streets.stream().filter(value -> normalize(value.name()).equals(normalize(input))).toList(); return matches.isEmpty() ? invalid(input, "street_not_found_for_postcode", matches) : valid(input, matches, null); }
    private static ValidationResult validateHouseNumber(Object input, ValidationResult street) {
        if (street == null || street.status() != ValidationStatus.VALID) return ne(input, "street_is_required_and_must_be_valid");
        Long number = positiveInteger(input); if (number == null) return invalid(input, "house_number_must_be_a_positive_integer", null);
        @SuppressWarnings("unchecked") List<Street> streets = (List<Street>) street.matches();
        List<Boolean> checks = streets.stream().map(value -> contains(value, number)).filter(Objects::nonNull).toList();
        return checks.isEmpty() || checks.contains(true) ? valid(input, streets, checks.isEmpty() ? "street_has_no_usable_range" : null) : invalid(input, null, streets);
    }
    private static Boolean contains(Street street, long number) { String start = number % 2 == 0 ? street.evenStart() : street.oddStart(); String end = number % 2 == 0 ? street.evenEnd() : street.oddEnd(); Long first = rangeNumber(start); if (first == null) return null; if (normalize(end == null ? "" : end).equals("τελ")) return number >= first; Long last = rangeNumber(end); return last == null ? null : number >= first && number <= last; }
    private static Long positiveInteger(Object value) { if (value instanceof Number number && number.longValue() > 0 && number.doubleValue() == number.longValue()) return number.longValue(); if (value instanceof String text && text.matches("\\d+") && Long.parseLong(text) > 0) return Long.parseLong(text); return null; }
    private static Long rangeNumber(String value) { var match = RANGE_NUMBER.matcher(value == null ? "" : value); return match.find() ? Long.valueOf(match.group(1)) : null; }
    private static String normalize(String value) { if (value == null) return ""; String normalized = Normalizer.normalize(value, Normalizer.Form.NFD).toLowerCase(Locale.ROOT); StringBuilder result = new StringBuilder(); normalized.codePoints().filter(c -> Character.getType(c) != Character.NON_SPACING_MARK && Character.isLetterOrDigit(c)).forEach(result::appendCodePoint); return result.toString(); }
    private static void limit(Integer value) { if (value != null && value <= 0) throw new IllegalArgumentException("limit must be a positive integer"); }
    private static ListOptions defaults(ListOptions options) { return options == null ? new ListOptions() : options; }
    private static EntityHierarchy emptyHierarchy() { return new EntityHierarchy(null, null, null, null, null, null); }
    private static Entity named(Entity entity) { return entity == null ? null : new Entity(entity.id(), entity.name(), null, null); }
    private static Entity coded(Entity entity) { return entity; }
    private static ValidationResult valid(Object input, List<?> matches, String reason) { return new ValidationResult(ValidationStatus.VALID, input, matches, reason); }
    private static ValidationResult invalid(Object input, String reason, List<?> matches) { return new ValidationResult(ValidationStatus.INVALID, input, matches, reason); }
    private static ValidationResult ne(Object input, String reason) { return input == null ? null : new ValidationResult(ValidationStatus.NOT_EVALUATED, input, null, reason); }
    private Entity entity(ResultSet row, boolean officialCode) throws SQLException { return new Entity(row.getLong(1), row.getString(2), officialCode ? row.getString(3) : null, null); }
    private Street street(ResultSet row) throws SQLException { return new Street(row.getLong(1), row.getString(2), row.getString(3), row.getString(4), row.getString(5), row.getString(6), row.getString(7)); }
    private PostcodeResult location(ResultSet row) throws SQLException { return new PostcodeResult(row.getString(1), nullableDouble(row, 2), nullableDouble(row, 3), row.getString(4), nullableLong(row, 5), nullableLong(row, 6), nullableLong(row, 7), null, null); }
    private static Long nullableLong(ResultSet row, int column) throws SQLException { long value = row.getLong(column); return row.wasNull() ? null : value; }
    private static Double nullableDouble(ResultSet row, int column) throws SQLException { double value = row.getDouble(column); return row.wasNull() ? null : value; }
    private <T> T one(String sql, Binder binder, Mapper<T> mapper) { List<T> values = all(sql, binder, mapper); return values.isEmpty() ? null : values.getFirst(); }
    private <T> List<T> all(String sql, Binder binder, Mapper<T> mapper) { try (PreparedStatement statement = connection().prepareStatement(sql)) { binder.bind(statement); try (ResultSet rows = statement.executeQuery()) { List<T> result = new ArrayList<>(); while (rows.next()) result.add(mapper.map(rows)); return result; } } catch (SQLException exception) { throw new PostalCodeException("SQLite query failed.", exception); } }
    private Connection connection() { if (connection == null) throw new IllegalStateException("PostalCodeClient is closed."); return connection; }
    @FunctionalInterface private interface Binder { void bind(PreparedStatement statement) throws SQLException; }
    @FunctionalInterface private interface Mapper<T> { T map(ResultSet row) throws SQLException; }
    public static final class PostalCodeException extends RuntimeException { public PostalCodeException(String message, Throwable cause) { super(message, cause); } }
}
