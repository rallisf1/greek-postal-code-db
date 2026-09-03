// Package postalcode provides offline, read-only Greek postal-code data.
package postalcode

// Entity is an administrative entity. OfficialCode is nil when it was not
// requested or when the source data has no official code for that entity.
type Entity struct {
	ID           int64              `json:"id"`
	Name         string             `json:"name"`
	OfficialCode *string            `json:"officialCode,omitempty"`
	Hierarchy    map[string]*Entity `json:"hierarchy,omitempty"`
}

// Street describes a street and its applicable odd/even house-number ranges.
type Street struct {
	ID        int64   `json:"id"`
	Postcode  string  `json:"postcode"`
	Name      string  `json:"name"`
	OddStart  *string `json:"oddStart"`
	OddEnd    *string `json:"oddEnd"`
	EvenStart *string `json:"evenStart"`
	EvenEnd   *string `json:"evenEnd"`
}

// PostcodeResult is the canonical location for a postcode.
type PostcodeResult struct {
	Postcode        string             `json:"postcode"`
	Latitude        *float64           `json:"latitude"`
	Longitude       *float64           `json:"longitude"`
	LocalArea       *string            `json:"localArea"`
	MunicipalUnitID *int64             `json:"municipalUnitId"`
	CommunityID     *int64             `json:"communityId"`
	MunicipalityID  *int64             `json:"municipalityId"`
	Hierarchy       map[string]*Entity `json:"hierarchy,omitempty"`
	Streets         []Street           `json:"streets,omitempty"`
}

// ListOptions applies to entity listing and search operations. A zero Limit
// returns every match. IncludeOfficialCode is ignored for regions.
type ListOptions struct {
	Limit               int
	IncludeHierarchy    bool
	IncludeOfficialCode bool
}

type RegionalUnitOptions struct {
	ListOptions
	RegionID *int64
}
type MunicipalityOptions struct {
	ListOptions
	RegionalUnitID *int64
}
type MunicipalityChildOptions struct {
	ListOptions
	MunicipalityID *int64
}

type PostcodeOptions struct {
	IncludeHierarchy bool
	IncludeStreets   bool
}

// AddressInput accepts locality references as either a name (string) or an
// integer ID. Leave optional fields nil when they should not be evaluated.
type AddressInput struct {
	Postcode      string
	Street        *string
	HouseNumber   any
	Municipality  any
	MunicipalUnit any
	Community     any
	RegionalUnit  any
	Region        any
}

type ValidationStatus string

const (
	Valid        ValidationStatus = "valid"
	Invalid      ValidationStatus = "invalid"
	NotEvaluated ValidationStatus = "not_evaluated"
)

// ValidationResult reports one independently evaluated address component.
// Matches contains []Entity, []Street, or []PostcodeResult depending on the
// component.
type ValidationResult struct {
	Status  ValidationStatus `json:"status"`
	Input   any              `json:"input"`
	Matches any              `json:"matches,omitempty"`
	Reason  string           `json:"reason,omitempty"`
}

// AddressValidation deliberately has no aggregate valid flag. Each supplied
// component is reported independently.
type AddressValidation struct {
	Postcode      ValidationResult  `json:"postcode"`
	Street        *ValidationResult `json:"street,omitempty"`
	HouseNumber   *ValidationResult `json:"houseNumber,omitempty"`
	Municipality  *ValidationResult `json:"municipality,omitempty"`
	MunicipalUnit *ValidationResult `json:"municipalUnit,omitempty"`
	Community     *ValidationResult `json:"community,omitempty"`
	RegionalUnit  *ValidationResult `json:"regionalUnit,omitempty"`
	Region        *ValidationResult `json:"region,omitempty"`
}
