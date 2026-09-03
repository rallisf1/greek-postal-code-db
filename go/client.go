package postalcode

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"

	_ "modernc.org/sqlite"
)

//go:embed data/library.sqlite
var embeddedDatabase []byte

var digits = regexp.MustCompile(`^\d{5}$`)
var houseNumber = regexp.MustCompile(`^\s*(\d+)`)

// Client owns a read-only connection to a temporary copy of the embedded
// database. Close releases the handle and removes that copy.
type Client struct {
	db   *sql.DB
	path string
}

// NewClient opens the bundled database read-only.
func NewClient() (*Client, error) {
	file, err := os.CreateTemp("", "greek-postal-code-db-*.sqlite")
	if err != nil {
		return nil, fmt.Errorf("create database file: %w", err)
	}
	path := file.Name()
	if _, err = file.Write(embeddedDatabase); err != nil {
		file.Close()
		os.Remove(path)
		return nil, fmt.Errorf("write database file: %w", err)
	}
	if err = file.Close(); err != nil {
		os.Remove(path)
		return nil, fmt.Errorf("close database file: %w", err)
	}
	db, err := sql.Open("sqlite", "file:"+filepath.ToSlash(path)+"?mode=ro")
	if err != nil {
		os.Remove(path)
		return nil, fmt.Errorf("open database: %w", err)
	}
	if err = db.Ping(); err != nil {
		db.Close()
		os.Remove(path)
		return nil, fmt.Errorf("open database: %w", err)
	}
	return &Client{db: db, path: path}, nil
}

func (c *Client) Close() error {
	if c.db == nil {
		return nil
	}
	err := c.db.Close()
	c.db = nil
	removeErr := os.Remove(c.path)
	if removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
		return errors.Join(err, removeErr)
	}
	return err
}

func (c *Client) ListRegions(ctx context.Context, options ListOptions) ([]Entity, error) {
	return c.listEntities(ctx, "regions", "", nil, options, false)
}
func (c *Client) ListRegionalUnits(ctx context.Context, options RegionalUnitOptions) ([]Entity, error) {
	return c.listEntities(ctx, "regional_units", "region_id", options.RegionID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) ListMunicipalities(ctx context.Context, options MunicipalityOptions) ([]Entity, error) {
	return c.listEntities(ctx, "municipalities", "regional_unit_id", options.RegionalUnitID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) ListMunicipalUnits(ctx context.Context, options MunicipalityChildOptions) ([]Entity, error) {
	return c.listEntities(ctx, "municipal_units", "municipality_id", options.MunicipalityID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) ListCommunities(ctx context.Context, options MunicipalityChildOptions) ([]Entity, error) {
	return c.listEntities(ctx, "communities", "municipality_id", options.MunicipalityID, options.ListOptions, options.IncludeOfficialCode)
}

func (c *Client) SearchRegions(ctx context.Context, query string, options ListOptions) ([]Entity, error) {
	return c.searchEntities(ctx, "regions", "", query, nil, options, false)
}
func (c *Client) SearchRegionalUnits(ctx context.Context, query string, options RegionalUnitOptions) ([]Entity, error) {
	return c.searchEntities(ctx, "regional_units", "region_id", query, options.RegionID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) SearchMunicipalities(ctx context.Context, query string, options MunicipalityOptions) ([]Entity, error) {
	return c.searchEntities(ctx, "municipalities", "regional_unit_id", query, options.RegionalUnitID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) SearchMunicipalUnits(ctx context.Context, query string, options MunicipalityChildOptions) ([]Entity, error) {
	return c.searchEntities(ctx, "municipal_units", "municipality_id", query, options.MunicipalityID, options.ListOptions, options.IncludeOfficialCode)
}
func (c *Client) SearchCommunities(ctx context.Context, query string, options MunicipalityChildOptions) ([]Entity, error) {
	return c.searchEntities(ctx, "communities", "municipality_id", query, options.MunicipalityID, options.ListOptions, options.IncludeOfficialCode)
}

func (c *Client) GetPostcode(ctx context.Context, postcode string, options PostcodeOptions) (*PostcodeResult, error) {
	if !digits.MatchString(postcode) {
		return nil, nil
	}
	if err := c.open(); err != nil {
		return nil, err
	}
	row := c.db.QueryRowContext(ctx, `SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?`, postcode)
	location, err := scanPostcode(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if options.IncludeHierarchy {
		location.Hierarchy, err = c.postcodeHierarchy(ctx, location)
		if err != nil {
			return nil, err
		}
	}
	if options.IncludeStreets {
		location.Streets, err = c.streets(ctx, postcode)
		if err != nil {
			return nil, err
		}
	}
	return &location, nil
}

func (c *Client) ValidateAddress(ctx context.Context, input AddressInput) (AddressValidation, error) {
	includeStreets := input.Street != nil || input.HouseNumber != nil
	postcode, err := c.GetPostcode(ctx, input.Postcode, PostcodeOptions{IncludeHierarchy: true, IncludeStreets: includeStreets})
	if err != nil {
		return AddressValidation{}, err
	}
	result := AddressValidation{Postcode: ValidationResult{Status: Invalid, Input: input.Postcode}}
	if !digits.MatchString(input.Postcode) {
		result.Postcode.Reason = "postcode_must_be_exactly_five_digits"
	} else if postcode == nil {
		result.Postcode.Reason = "postcode_not_found"
	} else {
		result.Postcode = ValidationResult{Status: Valid, Input: input.Postcode, Matches: []PostcodeResult{*postcode}}
	}
	if postcode == nil {
		if input.Street != nil {
			result.Street = notEvaluated(input.Street, "postcode_not_found")
		}
		if input.HouseNumber != nil {
			result.HouseNumber = notEvaluated(input.HouseNumber, "postcode_not_found")
		}
		if input.Municipality != nil {
			result.Municipality = notEvaluated(input.Municipality, "postcode_not_found")
		}
		if input.MunicipalUnit != nil {
			result.MunicipalUnit = notEvaluated(input.MunicipalUnit, "postcode_not_found")
		}
		if input.Community != nil {
			result.Community = notEvaluated(input.Community, "postcode_not_found")
		}
		if input.RegionalUnit != nil {
			result.RegionalUnit = notEvaluated(input.RegionalUnit, "postcode_not_found")
		}
		if input.Region != nil {
			result.Region = notEvaluated(input.Region, "postcode_not_found")
		}
		return result, nil
	}
	h := postcode.Hierarchy
	if input.Municipality != nil {
		value, e := c.validateReference(ctx, "municipalities", input.Municipality, h["municipality"])
		if e != nil {
			return result, e
		}
		result.Municipality = &value
	}
	if input.MunicipalUnit != nil {
		value, e := c.validateReference(ctx, "municipal_units", input.MunicipalUnit, h["municipalUnit"])
		if e != nil {
			return result, e
		}
		result.MunicipalUnit = &value
	}
	if input.Community != nil {
		value, e := c.validateReference(ctx, "communities", input.Community, h["community"])
		if e != nil {
			return result, e
		}
		result.Community = &value
	}
	if input.RegionalUnit != nil {
		value, e := c.validateReference(ctx, "regional_units", input.RegionalUnit, h["regionalUnit"])
		if e != nil {
			return result, e
		}
		result.RegionalUnit = &value
	}
	if input.Region != nil {
		value, e := c.validateReference(ctx, "regions", input.Region, h["region"])
		if e != nil {
			return result, e
		}
		result.Region = &value
	}
	if input.Street != nil {
		matches := make([]Street, 0)
		for _, street := range postcode.Streets {
			if normalizeName(street.Name) == normalizeName(*input.Street) {
				matches = append(matches, street)
			}
		}
		value := ValidationResult{Status: Valid, Input: *input.Street, Matches: matches}
		if len(matches) == 0 {
			value.Status = Invalid
			value.Reason = "street_not_found_for_postcode"
		}
		result.Street = &value
	}
	if input.HouseNumber != nil {
		if result.Street == nil || result.Street.Status != Valid {
			result.HouseNumber = notEvaluated(input.HouseNumber, "street_is_required_and_must_be_valid")
		} else if number, ok := positiveInteger(input.HouseNumber); !ok {
			result.HouseNumber = &ValidationResult{Status: Invalid, Input: input.HouseNumber, Reason: "house_number_must_be_a_positive_integer"}
		} else {
			streets := result.Street.Matches.([]Street)
			usable, matches := false, false
			for _, street := range streets {
				if contains := containsHouseNumber(street, number); contains != nil {
					usable = true
					matches = matches || *contains
				}
			}
			value := ValidationResult{Status: Valid, Input: input.HouseNumber, Matches: streets}
			if usable && !matches {
				value.Status = Invalid
			}
			if !usable {
				value.Reason = "street_has_no_usable_range"
			}
			result.HouseNumber = &value
		}
	}
	return result, nil
}

func (c *Client) listEntities(ctx context.Context, table, foreignKey string, parent *int64, options ListOptions, officialCode bool) ([]Entity, error) {
	if err := c.open(); err != nil {
		return nil, err
	}
	if options.Limit < 0 {
		return nil, fmt.Errorf("limit must not be negative")
	}
	columns := "id, name"
	if officialCode {
		columns += ", official_code"
	}
	query := "SELECT " + columns + " FROM " + table
	args := []any{}
	if foreignKey != "" && parent != nil {
		query += " WHERE " + foreignKey + " = ?"
		args = append(args, *parent)
	}
	query += " ORDER BY name, id"
	rows, err := c.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	entities := make([]Entity, 0)
	for rows.Next() {
		entity, err := scanEntity(rows, officialCode)
		if err != nil {
			return nil, err
		}
		if options.IncludeHierarchy {
			entity.Hierarchy, err = c.entityHierarchy(ctx, table, entity.ID)
			if err != nil {
				return nil, err
			}
		}
		entities = append(entities, entity)
		if options.Limit > 0 && len(entities) == options.Limit {
			break
		}
	}
	return entities, rows.Err()
}

func (c *Client) searchEntities(ctx context.Context, table, foreignKey, query string, parent *int64, options ListOptions, officialCode bool) ([]Entity, error) {
	normalized := normalizeName(query)
	if normalized == "" {
		return []Entity{}, nil
	}
	allOptions := options
	allOptions.Limit = 0
	allOptions.IncludeHierarchy = false
	entities, err := c.listEntities(ctx, table, foreignKey, parent, allOptions, officialCode)
	if err != nil {
		return nil, err
	}
	matches := make([]Entity, 0)
	for _, entity := range entities {
		if strings.HasPrefix(normalizeName(entity.Name), normalized) {
			if options.IncludeHierarchy {
				entity.Hierarchy, err = c.entityHierarchy(ctx, table, entity.ID)
				if err != nil {
					return nil, err
				}
			}
			matches = append(matches, entity)
			if options.Limit > 0 && len(matches) == options.Limit {
				break
			}
		}
	}
	return matches, nil
}

func (c *Client) streets(ctx context.Context, postcode string) ([]Street, error) {
	rows, err := c.db.QueryContext(ctx, `SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id`, postcode)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []Street{}
	for rows.Next() {
		var street Street
		if err := rows.Scan(&street.ID, &street.Postcode, &street.Name, &street.OddStart, &street.OddEnd, &street.EvenStart, &street.EvenEnd); err != nil {
			return nil, err
		}
		result = append(result, street)
	}
	return result, rows.Err()
}

func (c *Client) entityHierarchy(ctx context.Context, table string, id int64) (map[string]*Entity, error) {
	if table == "regions" {
		row := c.db.QueryRowContext(ctx, `SELECT decentralized_administration_id FROM regions WHERE id = ?`, id)
		var administrationID int64
		if err := row.Scan(&administrationID); err != nil {
			return nil, err
		}
		administration, err := c.named(ctx, "decentralized_administrations", administrationID)
		return map[string]*Entity{"decentralizedAdministration": administration}, err
	}
	if table == "regional_units" {
		return c.regionalUnitHierarchy(ctx, id)
	}
	if table == "municipalities" {
		return c.municipalityHierarchy(ctx, id)
	}
	row := c.db.QueryRowContext(ctx, "SELECT municipality_id FROM "+table+" WHERE id = ?", id)
	var municipalityID int64
	if err := row.Scan(&municipalityID); err != nil {
		return nil, err
	}
	return c.municipalityChildHierarchy(ctx, municipalityID)
}

func (c *Client) postcodeHierarchy(ctx context.Context, location PostcodeResult) (map[string]*Entity, error) {
	result := map[string]*Entity{}
	var err error
	if location.MunicipalUnitID != nil {
		result["municipalUnit"], err = c.coded(ctx, "municipal_units", *location.MunicipalUnitID)
		if err != nil {
			return nil, err
		}
	} else {
		result["municipalUnit"] = nil
	}
	if location.CommunityID != nil {
		result["community"], err = c.coded(ctx, "communities", *location.CommunityID)
		if err != nil {
			return nil, err
		}
	} else {
		result["community"] = nil
	}
	if location.MunicipalityID == nil {
		result["municipality"] = nil
		result["regionalUnit"] = nil
		result["region"] = nil
		result["decentralizedAdministration"] = nil
		return result, nil
	}
	result["municipality"], err = c.coded(ctx, "municipalities", *location.MunicipalityID)
	if err != nil {
		return nil, err
	}
	ancestors, err := c.municipalityHierarchy(ctx, *location.MunicipalityID)
	if err != nil {
		return nil, err
	}
	for key, value := range ancestors {
		result[key] = value
	}
	return result, nil
}

func (c *Client) regionalUnitHierarchy(ctx context.Context, unitID int64) (map[string]*Entity, error) {
	var regionID int64
	if err := c.db.QueryRowContext(ctx, `SELECT region_id FROM regional_units WHERE id = ?`, unitID).Scan(&regionID); err != nil {
		return nil, err
	}
	region, err := c.named(ctx, "regions", regionID)
	if err != nil {
		return nil, err
	}
	var administrationID int64
	if err := c.db.QueryRowContext(ctx, `SELECT decentralized_administration_id FROM regions WHERE id = ?`, regionID).Scan(&administrationID); err != nil {
		return nil, err
	}
	administration, err := c.named(ctx, "decentralized_administrations", administrationID)
	return map[string]*Entity{"region": region, "decentralizedAdministration": administration}, err
}
func (c *Client) municipalityHierarchy(ctx context.Context, municipalityID int64) (map[string]*Entity, error) {
	var unitID int64
	if err := c.db.QueryRowContext(ctx, `SELECT regional_unit_id FROM municipalities WHERE id = ?`, municipalityID).Scan(&unitID); err != nil {
		return nil, err
	}
	unit, err := c.coded(ctx, "regional_units", unitID)
	if err != nil {
		return nil, err
	}
	ancestors, err := c.regionalUnitHierarchy(ctx, unitID)
	if err != nil {
		return nil, err
	}
	ancestors["regionalUnit"] = unit
	return ancestors, nil
}
func (c *Client) municipalityChildHierarchy(ctx context.Context, municipalityID int64) (map[string]*Entity, error) {
	municipality, err := c.coded(ctx, "municipalities", municipalityID)
	if err != nil {
		return nil, err
	}
	ancestors, err := c.municipalityHierarchy(ctx, municipalityID)
	if err != nil {
		return nil, err
	}
	ancestors["municipality"] = municipality
	return ancestors, nil
}

func (c *Client) named(ctx context.Context, table string, id int64) (*Entity, error) {
	return c.loadEntity(ctx, table, id, false)
}
func (c *Client) coded(ctx context.Context, table string, id int64) (*Entity, error) {
	return c.loadEntity(ctx, table, id, true)
}
func (c *Client) loadEntity(ctx context.Context, table string, id int64, official bool) (*Entity, error) {
	columns := "id, name"
	if official {
		columns += ", official_code"
	}
	entity, err := scanEntity(c.db.QueryRowContext(ctx, "SELECT "+columns+" FROM "+table+" WHERE id = ?", id), official)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &entity, err
}

func (c *Client) validateReference(ctx context.Context, table string, reference any, linked *Entity) (ValidationResult, error) {
	if reference == nil {
		return ValidationResult{}, fmt.Errorf("reference must not be nil")
	}
	if name, ok := reference.(string); ok && normalizeName(name) == "" {
		return ValidationResult{Status: Invalid, Input: reference, Matches: []Entity{}, Reason: "reference_must_not_be_empty"}, nil
	}
	official := table != "regions"
	var matches []Entity
	if id, ok := entityID(reference); ok {
		entity, err := c.loadEntity(ctx, table, id, official)
		if err != nil {
			return ValidationResult{}, err
		}
		if entity != nil {
			matches = []Entity{*entity}
		} else {
			matches = []Entity{}
		}
	} else if name, ok := reference.(string); ok {
		all, err := c.listEntities(ctx, table, "", nil, ListOptions{IncludeOfficialCode: official}, official)
		if err != nil {
			return ValidationResult{}, err
		}
		matches = []Entity{}
		for _, entity := range all {
			if strings.HasPrefix(normalizeName(entity.Name), normalizeName(name)) {
				matches = append(matches, entity)
			}
		}
	} else {
		return ValidationResult{Status: Invalid, Input: reference, Matches: []Entity{}, Reason: "reference_must_be_a_name_or_id"}, nil
	}
	valid := false
	for _, entity := range matches {
		valid = valid || linked != nil && entity.ID == linked.ID
	}
	result := ValidationResult{Status: Invalid, Input: reference, Matches: matches}
	if valid {
		result.Status = Valid
	}
	if linked == nil {
		result.Reason = "postcode_has_no_linked_entity"
	}
	return result, nil
}

func scanEntity(row interface{ Scan(...any) error }, official bool) (Entity, error) {
	var entity Entity
	if official {
		var code sql.NullString
		err := row.Scan(&entity.ID, &entity.Name, &code)
		if code.Valid {
			entity.OfficialCode = &code.String
		}
		return entity, err
	}
	return entity, row.Scan(&entity.ID, &entity.Name)
}
func scanPostcode(row interface{ Scan(...any) error }) (PostcodeResult, error) {
	var result PostcodeResult
	var latitude, longitude sql.NullFloat64
	var local sql.NullString
	var municipalUnit, community, municipality sql.NullInt64
	err := row.Scan(&result.Postcode, &latitude, &longitude, &local, &municipalUnit, &community, &municipality)
	if latitude.Valid {
		result.Latitude = &latitude.Float64
	}
	if longitude.Valid {
		result.Longitude = &longitude.Float64
	}
	if local.Valid {
		result.LocalArea = &local.String
	}
	if municipalUnit.Valid {
		result.MunicipalUnitID = &municipalUnit.Int64
	}
	if community.Valid {
		result.CommunityID = &community.Int64
	}
	if municipality.Valid {
		result.MunicipalityID = &municipality.Int64
	}
	return result, err
}
func (c *Client) open() error {
	if c.db == nil {
		return errors.New("postal code client is closed")
	}
	return nil
}
func notEvaluated(input any, reason string) *ValidationResult {
	return &ValidationResult{Status: NotEvaluated, Input: input, Reason: reason}
}
func positiveInteger(value any) (int64, bool) {
	switch number := value.(type) {
	case int:
		if number > 0 {
			return int64(number), true
		}
	case int64:
		if number > 0 {
			return number, true
		}
	case string:
		parsed, err := strconv.ParseInt(number, 10, 64)
		if err == nil && parsed > 0 {
			return parsed, true
		}
	}
	return 0, false
}
func entityID(value any) (int64, bool) {
	switch number := value.(type) {
	case int:
		return int64(number), number > 0
	case int64:
		return number, number > 0
	}
	return 0, false
}
func containsHouseNumber(street Street, number int64) *bool {
	startText, endText := street.EvenStart, street.EvenEnd
	if number%2 == 1 {
		startText, endText = street.OddStart, street.OddEnd
	}
	start, ok := rangeNumber(startText)
	if !ok {
		return nil
	}
	end, hasEnd := rangeNumber(endText)
	if !hasEnd && normalizeName(deref(endText)) != "τελ" {
		return nil
	}
	result := number >= start && (normalizeName(deref(endText)) == "τελ" || number <= end)
	return &result
}
func rangeNumber(value *string) (int64, bool) {
	if value == nil {
		return 0, false
	}
	match := houseNumber.FindStringSubmatch(*value)
	if len(match) != 2 {
		return 0, false
	}
	number, err := strconv.ParseInt(match[1], 10, 64)
	return number, err == nil
}
func deref(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
func normalizeName(value string) string {
	value = strings.ToLower(value)
	value = strings.NewReplacer("ά", "α", "έ", "ε", "ή", "η", "ί", "ι", "ό", "ο", "ύ", "υ", "ώ", "ω", "ϊ", "ι", "ϋ", "υ", "ΐ", "ι", "ΰ", "υ", "ς", "σ").Replace(value)
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			return r
		}
		return -1
	}, value)
}
