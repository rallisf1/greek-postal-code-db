package io.github.rallisf1.greekpostalcode;

import java.util.List;

public final class Models {
    private Models() { }

    public record Entity(long id, String name, String officialCode, EntityHierarchy hierarchy) {
        public Entity(long id, String name) { this(id, name, null, null); }
    }
    public record EntityHierarchy(Entity decentralizedAdministration, Entity region, Entity regionalUnit, Entity municipality, Entity municipalUnit, Entity community) { }
    public record Street(long id, String postcode, String name, String oddStart, String oddEnd, String evenStart, String evenEnd) { }
    public record PostcodeResult(String postcode, Double latitude, Double longitude, String localArea, Long municipalUnitId, Long communityId, Long municipalityId, EntityHierarchy hierarchy, List<Street> streets) { }
    public record ListOptions(Integer limit, boolean includeHierarchy, boolean includeOfficialCode) {
        public ListOptions() { this(null, false, false); }
    }
    public record RegionalUnitOptions(Long regionId, Integer limit, boolean includeHierarchy, boolean includeOfficialCode) {
        public RegionalUnitOptions() { this(null, null, false, false); }
        ListOptions listOptions() { return new ListOptions(limit, includeHierarchy, includeOfficialCode); }
    }
    public record MunicipalityOptions(Long regionalUnitId, Integer limit, boolean includeHierarchy, boolean includeOfficialCode) {
        public MunicipalityOptions() { this(null, null, false, false); }
        ListOptions listOptions() { return new ListOptions(limit, includeHierarchy, includeOfficialCode); }
    }
    public record MunicipalityChildOptions(Long municipalityId, Integer limit, boolean includeHierarchy, boolean includeOfficialCode) {
        public MunicipalityChildOptions() { this(null, null, false, false); }
        ListOptions listOptions() { return new ListOptions(limit, includeHierarchy, includeOfficialCode); }
    }
    public record PostcodeOptions(boolean includeHierarchy, boolean includeStreets) { public PostcodeOptions() { this(false, false); } }

    public sealed interface LocalityReference permits LocalityId, LocalityName {
        static LocalityReference byId(long id) { return new LocalityId(id); }
        static LocalityReference byName(String name) { return new LocalityName(name); }
    }
    public record LocalityId(long id) implements LocalityReference { }
    public record LocalityName(String name) implements LocalityReference { }

    public record AddressInput(String postcode, String street, Object houseNumber, LocalityReference municipality, LocalityReference municipalUnit, LocalityReference community, LocalityReference regionalUnit, LocalityReference region) {
        public AddressInput(String postcode) { this(postcode, null, null, null, null, null, null, null); }
    }
    public enum ValidationStatus { VALID, INVALID, NOT_EVALUATED }
    public record ValidationResult(ValidationStatus status, Object input, List<?> matches, String reason) { }
    public record AddressValidation(ValidationResult postcode, ValidationResult street, ValidationResult houseNumber, ValidationResult municipality, ValidationResult municipalUnit, ValidationResult community, ValidationResult regionalUnit, ValidationResult region) { }
}
