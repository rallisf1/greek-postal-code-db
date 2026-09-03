from __future__ import annotations

from contextlib import ExitStack
from importlib import resources
import re
import sqlite3
import unicodedata
from typing import Any


_POSTCODE = re.compile(r"^\d{5}$")
_RANGE_NUMBER = re.compile(r"^\s*(\d+)")


def create_postal_code_client() -> PostalCodeClient:
    """Open the bundled SQLite database read-only."""
    return PostalCodeClient()


class PostalCodeClient:
    """A read-only, offline client for the bundled Greek postal-code database."""

    def __init__(self) -> None:
        self._resources = ExitStack()
        database = resources.files("greek_postal_code_db.data").joinpath("library.sqlite")
        path = self._resources.enter_context(resources.as_file(database))
        self._connection: sqlite3.Connection | None = sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)
        self._connection.row_factory = sqlite3.Row
        self._connection.execute("PRAGMA query_only = ON")

    def close(self) -> None:
        """Close the read-only database handle."""
        if self._connection is not None:
            self._connection.close()
            self._connection = None
        self._resources.close()

    def __enter__(self) -> PostalCodeClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def list_regions(self, *, limit: int | None = None, include_hierarchy: bool = False) -> list[dict[str, Any]]:
        return self._list_entities("regions", None, None, limit, include_hierarchy, False)

    def list_regional_units(self, *, region_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._list_entities("regional_units", "region_id", region_id, limit, include_hierarchy, include_official_code)

    def list_municipalities(self, *, regional_unit_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._list_entities("municipalities", "regional_unit_id", regional_unit_id, limit, include_hierarchy, include_official_code)

    def list_municipal_units(self, *, municipality_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._list_entities("municipal_units", "municipality_id", municipality_id, limit, include_hierarchy, include_official_code)

    def list_communities(self, *, municipality_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._list_entities("communities", "municipality_id", municipality_id, limit, include_hierarchy, include_official_code)

    def search_regions(self, query: str, *, limit: int | None = None, include_hierarchy: bool = False) -> list[dict[str, Any]]:
        return self._search_entities("regions", None, query, None, limit, include_hierarchy, False)

    def search_regional_units(self, query: str, *, region_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._search_entities("regional_units", "region_id", query, region_id, limit, include_hierarchy, include_official_code)

    def search_municipalities(self, query: str, *, regional_unit_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._search_entities("municipalities", "regional_unit_id", query, regional_unit_id, limit, include_hierarchy, include_official_code)

    def search_municipal_units(self, query: str, *, municipality_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._search_entities("municipal_units", "municipality_id", query, municipality_id, limit, include_hierarchy, include_official_code)

    def search_communities(self, query: str, *, municipality_id: int | None = None, limit: int | None = None, include_hierarchy: bool = False, include_official_code: bool = False) -> list[dict[str, Any]]:
        return self._search_entities("communities", "municipality_id", query, municipality_id, limit, include_hierarchy, include_official_code)

    def get_postcode(self, postcode: str, *, include_hierarchy: bool = False, include_streets: bool = False) -> dict[str, Any] | None:
        if not _POSTCODE.fullmatch(postcode):
            return None
        row = self._one("SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode = ?", (postcode,))
        if row is None:
            return None
        result = self._location(row)
        if include_hierarchy:
            result["hierarchy"] = self._postcode_hierarchy(result)
        if include_streets:
            result["streets"] = [self._street(row) for row in self._all("SELECT id, postcode, name, odd_start, odd_end, even_start, even_end FROM streets WHERE postcode = ? ORDER BY name, id", (postcode,))]
        return result

    def validate_address(self, postcode: str, *, street: str | None = None, house_number: str | int | None = None, municipality: str | int | None = None, municipal_unit: str | int | None = None, community: str | int | None = None, regional_unit: str | int | None = None, region: str | int | None = None) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {"postcode": {"status": "invalid", "input": postcode}}
        value = self.get_postcode(postcode, include_hierarchy=True, include_streets=street is not None or house_number is not None)
        if not _POSTCODE.fullmatch(postcode):
            result["postcode"]["reason"] = "postcode_must_be_exactly_five_digits"
        elif value is None:
            result["postcode"]["reason"] = "postcode_not_found"
        else:
            result["postcode"] = {"status": "valid", "input": postcode, "matches": [value]}

        references = {"municipality": (municipality, "municipalities"), "municipalUnit": (municipal_unit, "municipal_units"), "community": (community, "communities"), "regionalUnit": (regional_unit, "regional_units"), "region": (region, "regions")}
        if value is None:
            if street is not None: result["street"] = self._not_evaluated(street, "postcode_not_found")
            if house_number is not None: result["houseNumber"] = self._not_evaluated(house_number, "postcode_not_found")
            for key, (reference, _) in references.items():
                if reference is not None: result[key] = self._not_evaluated(reference, "postcode_not_found")
            return result

        hierarchy = value["hierarchy"]
        for key, (reference, table) in references.items():
            if reference is not None:
                result[key] = self._validate_reference(table, reference, hierarchy.get(key))
        if street is not None:
            matches = [candidate for candidate in value.get("streets", []) if _normalize_name(candidate["name"]) == _normalize_name(street)]
            result["street"] = {"status": "valid" if matches else "invalid", "input": street, "matches": matches}
            if not matches: result["street"]["reason"] = "street_not_found_for_postcode"
        if house_number is not None:
            if result.get("street", {}).get("status") != "valid":
                result["houseNumber"] = self._not_evaluated(house_number, "street_is_required_and_must_be_valid")
            elif not _positive_integer(house_number):
                result["houseNumber"] = {"status": "invalid", "input": house_number, "reason": "house_number_must_be_a_positive_integer"}
            else:
                matches = result["street"]["matches"]
                checks = [_contains_house_number(candidate, int(house_number)) for candidate in matches]
                usable = [check for check in checks if check is not None]
                result["houseNumber"] = {"status": "valid" if not usable or any(usable) else "invalid", "input": house_number, "matches": matches}
                if not usable: result["houseNumber"]["reason"] = "street_has_no_usable_range"
        return result

    def _list_entities(self, table: str, foreign_key: str | None, parent_id: int | None, limit: int | None, include_hierarchy: bool, include_official_code: bool) -> list[dict[str, Any]]:
        _validate_limit(limit)
        columns = "id, name" + (", official_code" if include_official_code else "")
        if foreign_key is not None and parent_id is not None:
            rows = self._all(f"SELECT {columns} FROM {table} WHERE {foreign_key} = ? ORDER BY name, id", (parent_id,))
        else:
            rows = self._all(f"SELECT {columns} FROM {table} ORDER BY name, id")
        result = [self._with_hierarchy(table, self._entity(row, include_official_code), include_hierarchy) for row in rows]
        return result if limit is None else result[:limit]

    def _search_entities(self, table: str, foreign_key: str | None, query: str, parent_id: int | None, limit: int | None, include_hierarchy: bool, include_official_code: bool) -> list[dict[str, Any]]:
        _validate_limit(limit)
        normalized = _normalize_name(query)
        if not normalized: return []
        candidates = self._list_entities(table, foreign_key, parent_id, None, False, include_official_code)
        matches = [self._with_hierarchy(table, candidate, include_hierarchy) for candidate in candidates if _normalize_name(candidate["name"]).startswith(normalized)]
        return matches if limit is None else matches[:limit]

    def _with_hierarchy(self, table: str, entity: dict[str, Any], include: bool) -> dict[str, Any]:
        if include: entity["hierarchy"] = self._entity_hierarchy(table, entity["id"])
        return entity

    def _entity_hierarchy(self, table: str, identifier: int) -> dict[str, Any]:
        if table == "regions":
            row = self._one("SELECT decentralized_administration_id FROM regions WHERE id = ?", (identifier,))
            return {"decentralizedAdministration": self._named(self._one("SELECT id, name FROM decentralized_administrations WHERE id = ?", (row["decentralized_administration_id"],))) if row else None}
        if table == "regional_units": return self._regional_unit_hierarchy(identifier)
        if table == "municipalities": return self._municipality_hierarchy(identifier)
        row = self._one(f"SELECT municipality_id FROM {table} WHERE id = ?", (identifier,))
        return self._municipality_child_hierarchy(row["municipality_id"]) if row else {"municipality": None, "regionalUnit": None, "region": None, "decentralizedAdministration": None}

    def _postcode_hierarchy(self, location: dict[str, Any]) -> dict[str, Any]:
        municipality = self._one("SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?", (location["municipalityId"],)) if location["municipalityId"] is not None else None
        result = {"municipalUnit": self._coded(self._one("SELECT id, name, official_code FROM municipal_units WHERE id = ?", (location["municipalUnitId"],))) if location["municipalUnitId"] is not None else None, "community": self._coded(self._one("SELECT id, name, official_code FROM communities WHERE id = ?", (location["communityId"],))) if location["communityId"] is not None else None, "municipality": self._coded(municipality)}
        result.update(self._municipality_hierarchy(municipality["id"]) if municipality else {"regionalUnit": None, "region": None, "decentralizedAdministration": None})
        return result

    def _regional_unit_hierarchy(self, identifier: int) -> dict[str, Any]:
        unit = self._one("SELECT region_id FROM regional_units WHERE id = ?", (identifier,))
        region = self._one("SELECT id, name, decentralized_administration_id FROM regions WHERE id = ?", (unit["region_id"],)) if unit else None
        return {"region": self._named(region), "decentralizedAdministration": self._named(self._one("SELECT id, name FROM decentralized_administrations WHERE id = ?", (region["decentralized_administration_id"],))) if region else None}

    def _municipality_hierarchy(self, identifier: int) -> dict[str, Any]:
        municipality = self._one("SELECT regional_unit_id FROM municipalities WHERE id = ?", (identifier,))
        unit = self._one("SELECT id, name, region_id, official_code FROM regional_units WHERE id = ?", (municipality["regional_unit_id"],)) if municipality else None
        result = self._regional_unit_hierarchy(unit["id"]) if unit else {"region": None, "decentralizedAdministration": None}
        result["regionalUnit"] = self._coded(unit)
        return result

    def _municipality_child_hierarchy(self, municipality_id: int) -> dict[str, Any]:
        municipality = self._one("SELECT id, name, regional_unit_id, official_code FROM municipalities WHERE id = ?", (municipality_id,))
        result = self._municipality_hierarchy(municipality["id"]) if municipality else {"regionalUnit": None, "region": None, "decentralizedAdministration": None}
        result["municipality"] = self._coded(municipality)
        return result

    def _validate_reference(self, table: str, reference: str | int, linked: dict[str, Any] | None) -> dict[str, Any]:
        if isinstance(reference, str) and not _normalize_name(reference): return {"status": "invalid", "input": reference, "matches": [], "reason": "reference_must_not_be_empty"}
        if not isinstance(reference, (str, int)) or isinstance(reference, bool): return {"status": "invalid", "input": reference, "matches": [], "reason": "reference_must_be_a_name_or_id"}
        official = table != "regions"
        columns = "id, name" + (", official_code" if official else "")
        if isinstance(reference, int):
            matches = [self._entity(row, official) for row in self._all(f"SELECT {columns} FROM {table} WHERE id = ?", (reference,))]
        else:
            matches = [self._entity(row, official) for row in self._all(f"SELECT {columns} FROM {table} ORDER BY name, id") if _normalize_name(self._entity(row, official)["name"]).startswith(_normalize_name(reference))]
        valid = linked is not None and any(candidate["id"] == linked["id"] for candidate in matches)
        result = {"status": "valid" if valid else "invalid", "input": reference, "matches": matches}
        if linked is None: result["reason"] = "postcode_has_no_linked_entity"
        return result

    def _all(self, sql: str, parameters: tuple[Any, ...] = ()) -> list[sqlite3.Row]:
        return list(self._connection_or_raise().execute(sql, parameters))

    def _one(self, sql: str, parameters: tuple[Any, ...] = ()) -> sqlite3.Row | None:
        return self._connection_or_raise().execute(sql, parameters).fetchone()

    def _connection_or_raise(self) -> sqlite3.Connection:
        if self._connection is None: raise RuntimeError("PostalCodeClient is closed")
        return self._connection

    @staticmethod
    def _entity(row: sqlite3.Row, include_official_code: bool) -> dict[str, Any]:
        result: dict[str, Any] = {"id": row["id"], "name": row["name"]}
        if include_official_code: result["officialCode"] = row["official_code"]
        return result

    @staticmethod
    def _named(row: sqlite3.Row | None) -> dict[str, Any] | None: return PostalCodeClient._entity(row, False) if row else None
    @staticmethod
    def _coded(row: sqlite3.Row | None) -> dict[str, Any] | None: return PostalCodeClient._entity(row, True) if row else None
    @staticmethod
    def _street(row: sqlite3.Row) -> dict[str, Any]: return {"id": row["id"], "postcode": row["postcode"], "name": row["name"], "oddStart": row["odd_start"], "oddEnd": row["odd_end"], "evenStart": row["even_start"], "evenEnd": row["even_end"]}
    @staticmethod
    def _location(row: sqlite3.Row) -> dict[str, Any]: return {"postcode": row["postcode"], "latitude": row["latitude"], "longitude": row["longitude"], "localArea": row["local_area"], "municipalUnitId": row["municipal_unit_id"], "communityId": row["community_id"], "municipalityId": row["municipality_id"]}
    @staticmethod
    def _not_evaluated(value: Any, reason: str) -> dict[str, Any]: return {"status": "not_evaluated", "input": value, "reason": reason}


def _validate_limit(limit: int | None) -> None:
    if limit is not None and (not isinstance(limit, int) or isinstance(limit, bool) or limit <= 0): raise ValueError("limit must be a positive integer")


def _positive_integer(value: str | int) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0 or isinstance(value, str) and value.isdigit() and int(value) > 0


def _range_number(value: str | None) -> int | None:
    match = _RANGE_NUMBER.match(value or "")
    return int(match.group(1)) if match else None


def _contains_house_number(street: dict[str, Any], number: int) -> bool | None:
    start_key, end_key = ("oddStart", "oddEnd") if number % 2 else ("evenStart", "evenEnd")
    start, end_text = _range_number(street[start_key]), street[end_key]
    end = _range_number(end_text)
    if start is None or end is None and _normalize_name(end_text or "") != "τελ": return None
    return number >= start and (_normalize_name(end_text or "") == "τελ" or number <= end)


def _normalize_name(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", value).lower()
    return "".join(character for character in decomposed if not unicodedata.combining(character) and character.isalnum())
