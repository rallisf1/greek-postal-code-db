//! Offline, read-only Greek postal-code data.

use rusqlite::{Connection, OpenFlags, OptionalExtension, Row};
use serde_json::{Map, Value, json};
use std::{io::Write, path::PathBuf};
use tempfile::NamedTempFile;
use unicode_normalization::UnicodeNormalization;

const DATABASE: &[u8] = include_bytes!("../data/library.sqlite");

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("SQLite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("limit must be a positive integer")]
    InvalidLimit,
    #[error("postal code client is closed")]
    Closed,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Default, Clone, Copy)]
pub struct ListOptions {
    pub limit: Option<usize>,
    pub include_hierarchy: bool,
    pub include_official_code: bool,
}
#[derive(Default, Clone, Copy)]
pub struct PostcodeOptions {
    pub include_hierarchy: bool,
    pub include_streets: bool,
}
#[derive(Default)]
pub struct AddressInput {
    pub postcode: String,
    pub street: Option<String>,
    pub house_number: Option<i64>,
    pub municipality: Option<Value>,
    pub municipal_unit: Option<Value>,
    pub community: Option<Value>,
    pub regional_unit: Option<Value>,
    pub region: Option<Value>,
}

/// A read-only connection to a temporary copy of the embedded database.
pub struct PostalCodeClient {
    connection: Option<Connection>,
    database_path: PathBuf,
}

pub fn create_postal_code_client() -> Result<PostalCodeClient> {
    PostalCodeClient::new()
}

impl PostalCodeClient {
    pub fn new() -> Result<Self> {
        let mut file = NamedTempFile::new()?;
        file.write_all(DATABASE)?;
        let database_path = file
            .into_temp_path()
            .keep()
            .map_err(|error| Error::Io(error.error))?;
        let connection =
            Connection::open_with_flags(&database_path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        connection.execute_batch("PRAGMA query_only = ON")?;
        Ok(Self {
            connection: Some(connection),
            database_path,
        })
    }
    pub fn close(mut self) -> Result<()> {
        if let Some(connection) = self.connection.take() {
            connection
                .close()
                .map_err(|(_, error)| Error::Sqlite(error))?;
        }
        let _ = std::fs::remove_file(self.database_path);
        Ok(())
    }
    pub fn list_regions(&self, options: ListOptions) -> Result<Vec<Value>> {
        self.list("regions", None, None, options, false)
    }
    pub fn list_regional_units(
        &self,
        region_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.list(
            "regional_units",
            Some("region_id"),
            region_id,
            options,
            options.include_official_code,
        )
    }
    pub fn list_municipalities(
        &self,
        regional_unit_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.list(
            "municipalities",
            Some("regional_unit_id"),
            regional_unit_id,
            options,
            options.include_official_code,
        )
    }
    pub fn list_municipal_units(
        &self,
        municipality_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.list(
            "municipal_units",
            Some("municipality_id"),
            municipality_id,
            options,
            options.include_official_code,
        )
    }
    pub fn list_communities(
        &self,
        municipality_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.list(
            "communities",
            Some("municipality_id"),
            municipality_id,
            options,
            options.include_official_code,
        )
    }
    pub fn search_regions(&self, query: &str, options: ListOptions) -> Result<Vec<Value>> {
        self.search("regions", None, query, None, options, false)
    }
    pub fn search_regional_units(
        &self,
        query: &str,
        region_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.search(
            "regional_units",
            Some("region_id"),
            query,
            region_id,
            options,
            options.include_official_code,
        )
    }
    pub fn search_municipalities(
        &self,
        query: &str,
        regional_unit_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.search(
            "municipalities",
            Some("regional_unit_id"),
            query,
            regional_unit_id,
            options,
            options.include_official_code,
        )
    }
    pub fn search_municipal_units(
        &self,
        query: &str,
        municipality_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.search(
            "municipal_units",
            Some("municipality_id"),
            query,
            municipality_id,
            options,
            options.include_official_code,
        )
    }
    pub fn search_communities(
        &self,
        query: &str,
        municipality_id: Option<i64>,
        options: ListOptions,
    ) -> Result<Vec<Value>> {
        self.search(
            "communities",
            Some("municipality_id"),
            query,
            municipality_id,
            options,
            options.include_official_code,
        )
    }

    pub fn get_postcode(&self, postcode: &str, options: PostcodeOptions) -> Result<Option<Value>> {
        if postcode.len() != 5 || !postcode.bytes().all(|byte| byte.is_ascii_digit()) {
            return Ok(None);
        }
        let row = self.connection()?.query_row("SELECT postcode, latitude, longitude, local_area, municipal_unit_id, community_id, municipality_id FROM locations WHERE postcode=?", [postcode], postcode_value).optional()?;
        let Some(mut result) = row else {
            return Ok(None);
        };
        if options.include_hierarchy {
            result["hierarchy"] = self.postcode_hierarchy(&result)?;
        }
        if options.include_streets {
            result["streets"] = Value::Array(self.streets(postcode)?);
        }
        Ok(Some(result))
    }

    pub fn validate_address(&self, input: AddressInput) -> Result<Value> {
        let postcode = self.get_postcode(
            &input.postcode,
            PostcodeOptions {
                include_hierarchy: true,
                include_streets: input.street.is_some() || input.house_number.is_some(),
            },
        )?;
        let mut result = Map::new();
        result.insert("postcode".into(), if input.postcode.len() != 5 || !input.postcode.bytes().all(|b| b.is_ascii_digit()) { json!({"status":"invalid","input":input.postcode,"reason":"postcode_must_be_exactly_five_digits"}) } else if let Some(value) = &postcode { json!({"status":"valid","input":input.postcode,"matches":[value]}) } else { json!({"status":"invalid","input":input.postcode,"reason":"postcode_not_found"}) });
        let references = [
            ("municipality", "municipalities", &input.municipality),
            ("municipalUnit", "municipal_units", &input.municipal_unit),
            ("community", "communities", &input.community),
            ("regionalUnit", "regional_units", &input.regional_unit),
            ("region", "regions", &input.region),
        ];
        let Some(postcode) = postcode else {
            for (key, _, reference) in references {
                if let Some(value) = reference {
                    result.insert(key.into(), not_evaluated(value, "postcode_not_found"));
                }
            }
            if let Some(street) = input.street {
                result.insert(
                    "street".into(),
                    not_evaluated(&street, "postcode_not_found"),
                );
            }
            if let Some(number) = input.house_number {
                result.insert(
                    "houseNumber".into(),
                    not_evaluated(&number, "postcode_not_found"),
                );
            }
            return Ok(Value::Object(result));
        };
        let hierarchy = postcode["hierarchy"].as_object().unwrap();
        for (key, table, reference) in references {
            if let Some(reference) = reference {
                result.insert(
                    key.into(),
                    self.validate_reference(table, reference, hierarchy.get(key))?,
                );
            }
        }
        if let Some(street) = input.street {
            let matches: Vec<Value> = postcode["streets"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|candidate| {
                    normalize(candidate["name"].as_str().unwrap()) == normalize(&street)
                })
                .cloned()
                .collect();
            result.insert("street".into(), if matches.is_empty() { json!({"status":"invalid","input":street,"matches":[],"reason":"street_not_found_for_postcode"}) } else { json!({"status":"valid","input":street,"matches":matches}) });
        }
        if let Some(number) = input.house_number {
            let street = result.get("street");
            if street.and_then(|value| value["status"].as_str()) != Some("valid") {
                result.insert(
                    "houseNumber".into(),
                    not_evaluated(&number, "street_is_required_and_must_be_valid"),
                );
            } else if number <= 0 {
                result.insert("houseNumber".into(), json!({"status":"invalid","input":number,"reason":"house_number_must_be_a_positive_integer"}));
            } else {
                let matches = street.unwrap()["matches"].as_array().unwrap();
                let checks: Vec<Option<bool>> = matches
                    .iter()
                    .map(|value| contains_house_number(value, number))
                    .collect();
                let usable: Vec<bool> = checks.into_iter().flatten().collect();
                result.insert("houseNumber".into(), if usable.is_empty() { json!({"status":"valid","input":number,"matches":matches,"reason":"street_has_no_usable_range"}) } else { json!({"status":if usable.iter().any(|value| *value) {"valid"} else {"invalid"},"input":number,"matches":matches}) });
            }
        }
        Ok(Value::Object(result))
    }

    fn list(
        &self,
        table: &str,
        foreign: Option<&str>,
        parent: Option<i64>,
        options: ListOptions,
        coded: bool,
    ) -> Result<Vec<Value>> {
        if matches!(options.limit, Some(0)) {
            return Err(Error::InvalidLimit);
        };
        let columns = if coded {
            "id,name,official_code"
        } else {
            "id,name"
        };
        let query = match (foreign, parent) {
            (Some(key), Some(_)) => {
                format!("SELECT {columns} FROM {table} WHERE {key}=? ORDER BY name,id")
            }
            _ => format!("SELECT {columns} FROM {table} ORDER BY name,id"),
        };
        let mut statement = self.connection()?.prepare(&query)?;
        let mut rows = if let Some(id) = parent {
            statement.query([id])?
        } else {
            statement.query([])?
        };
        let mut values = Vec::new();
        while let Some(row) = rows.next()? {
            let mut value = entity_value(row, coded)?;
            if options.include_hierarchy {
                value["hierarchy"] = self.entity_hierarchy(table, value["id"].as_i64().unwrap())?;
            }
            values.push(value);
            if options.limit.is_some_and(|limit| values.len() == limit) {
                break;
            }
        }
        Ok(values)
    }
    fn search(
        &self,
        table: &str,
        foreign: Option<&str>,
        query: &str,
        parent: Option<i64>,
        mut options: ListOptions,
        coded: bool,
    ) -> Result<Vec<Value>> {
        let target = normalize(query);
        if target.is_empty() {
            return Ok(vec![]);
        };
        let limit = options.limit;
        let include_hierarchy = options.include_hierarchy;
        options.limit = None;
        options.include_hierarchy = false;
        let mut values = self.list(table, foreign, parent, options, coded)?;
        values.retain(|value| normalize(value["name"].as_str().unwrap()).starts_with(&target));
        if include_hierarchy {
            for value in &mut values {
                value["hierarchy"] = self.entity_hierarchy(table, value["id"].as_i64().unwrap())?;
            }
        }
        if let Some(limit) = limit {
            values.truncate(limit);
        }
        Ok(values)
    }
    fn streets(&self, postcode: &str) -> Result<Vec<Value>> {
        let mut statement = self.connection()?.prepare("SELECT id,postcode,name,odd_start,odd_end,even_start,even_end FROM streets WHERE postcode=? ORDER BY name,id")?;
        Ok(statement
            .query_map([postcode], street_value)?
            .collect::<std::result::Result<_, _>>()?)
    }
    fn entity_hierarchy(&self, table: &str, id: i64) -> Result<Value> {
        let mut result = Map::new();
        if table == "regions" {
            let administration: i64 = self.connection()?.query_row(
                "SELECT decentralized_administration_id FROM regions WHERE id=?",
                [id],
                |row| row.get(0),
            )?;
            result.insert(
                "decentralizedAdministration".into(),
                self.named("decentralized_administrations", administration)?,
            );
        } else if table == "regional_units" {
            return self.regional_unit_hierarchy(id);
        } else if table == "municipalities" {
            return self.municipality_hierarchy(id);
        } else {
            let municipality: i64 = self.connection()?.query_row(
                &format!("SELECT municipality_id FROM {table} WHERE id=?"),
                [id],
                |row| row.get(0),
            )?;
            return self.municipality_child_hierarchy(municipality);
        }
        Ok(Value::Object(result))
    }
    fn postcode_hierarchy(&self, value: &Value) -> Result<Value> {
        let mut result = Map::new();
        for (key, table, id) in [
            (
                "municipalUnit",
                "municipal_units",
                value["municipalUnitId"].as_i64(),
            ),
            ("community", "communities", value["communityId"].as_i64()),
        ] {
            result.insert(
                key.into(),
                match id {
                    Some(id) => self.coded(table, id)?,
                    None => Value::Null,
                },
            );
        }
        let municipality = value["municipalityId"].as_i64();
        result.insert(
            "municipality".into(),
            match municipality {
                Some(id) => self.coded("municipalities", id)?,
                None => Value::Null,
            },
        );
        if let Some(id) = municipality {
            let ancestors = self.municipality_hierarchy(id)?;
            result.extend(ancestors.as_object().unwrap().clone());
        } else {
            for key in ["regionalUnit", "region", "decentralizedAdministration"] {
                result.insert(key.into(), Value::Null);
            }
        }
        Ok(Value::Object(result))
    }
    fn regional_unit_hierarchy(&self, id: i64) -> Result<Value> {
        let region: i64 = self.connection()?.query_row(
            "SELECT region_id FROM regional_units WHERE id=?",
            [id],
            |row| row.get(0),
        )?;
        let administration: i64 = self.connection()?.query_row(
            "SELECT decentralized_administration_id FROM regions WHERE id=?",
            [region],
            |row| row.get(0),
        )?;
        Ok(
            json!({"region":self.named("regions",region)?,"decentralizedAdministration":self.named("decentralized_administrations",administration)?}),
        )
    }
    fn municipality_hierarchy(&self, id: i64) -> Result<Value> {
        let unit: i64 = self.connection()?.query_row(
            "SELECT regional_unit_id FROM municipalities WHERE id=?",
            [id],
            |row| row.get(0),
        )?;
        let mut result = self.regional_unit_hierarchy(unit)?;
        result["regionalUnit"] = self.coded("regional_units", unit)?;
        Ok(result)
    }
    fn municipality_child_hierarchy(&self, id: i64) -> Result<Value> {
        let mut result = self.municipality_hierarchy(id)?;
        result["municipality"] = self.coded("municipalities", id)?;
        Ok(result)
    }
    fn named(&self, table: &str, id: i64) -> Result<Value> {
        self.load_entity(table, id, false)
    }
    fn coded(&self, table: &str, id: i64) -> Result<Value> {
        self.load_entity(table, id, true)
    }
    fn load_entity(&self, table: &str, id: i64, coded: bool) -> Result<Value> {
        let columns = if coded {
            "id,name,official_code"
        } else {
            "id,name"
        };
        Ok(self.connection()?.query_row(
            &format!("SELECT {columns} FROM {table} WHERE id=?"),
            [id],
            |row| entity_value(row, coded),
        )?)
    }
    fn validate_reference(
        &self,
        table: &str,
        reference: &Value,
        linked: Option<&Value>,
    ) -> Result<Value> {
        if let Some(name) = reference.as_str() {
            if normalize(name).is_empty() {
                return Ok(
                    json!({"status":"invalid","input":reference,"matches":[],"reason":"reference_must_not_be_empty"}),
                );
            }
        }
        let coded = table != "regions";
        let matches = if let Some(id) = reference.as_i64() {
            match self.load_entity(table, id, coded) {
                Ok(value) => vec![value],
                Err(Error::Sqlite(rusqlite::Error::QueryReturnedNoRows)) => vec![],
                Err(error) => return Err(error),
            }
        } else if let Some(name) = reference.as_str() {
            self.list(
                table,
                None,
                None,
                ListOptions {
                    include_official_code: coded,
                    ..Default::default()
                },
                coded,
            )?
            .into_iter()
            .filter(|value| {
                normalize(value["name"].as_str().unwrap()).starts_with(&normalize(name))
            })
            .collect()
        } else {
            return Ok(
                json!({"status":"invalid","input":reference,"matches":[],"reason":"reference_must_be_a_name_or_id"}),
            );
        };
        let valid =
            linked.is_some_and(|linked| matches.iter().any(|value| value["id"] == linked["id"]));
        Ok(if linked.is_none() {
            json!({"status":"invalid","input":reference,"matches":matches,"reason":"postcode_has_no_linked_entity"})
        } else {
            json!({"status":if valid {"valid"} else {"invalid"},"input":reference,"matches":matches})
        })
    }
    fn connection(&self) -> Result<&Connection> {
        self.connection.as_ref().ok_or(Error::Closed)
    }
}

fn entity_value(row: &Row<'_>, coded: bool) -> rusqlite::Result<Value> {
    let mut value = json!({"id":row.get::<_,i64>(0)?,"name":row.get::<_,String>(1)?});
    if coded {
        value["officialCode"] = match row.get::<_, Option<String>>(2)? {
            Some(code) => Value::String(code),
            None => Value::Null,
        };
    }
    Ok(value)
}
fn street_value(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(
        json!({"id":row.get::<_,i64>(0)?,"postcode":row.get::<_,String>(1)?,"name":row.get::<_,String>(2)?,"oddStart":row.get::<_,Option<String>>(3)?,"oddEnd":row.get::<_,Option<String>>(4)?,"evenStart":row.get::<_,Option<String>>(5)?,"evenEnd":row.get::<_,Option<String>>(6)?}),
    )
}
fn postcode_value(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(
        json!({"postcode":row.get::<_,String>(0)?,"latitude":row.get::<_,Option<f64>>(1)?,"longitude":row.get::<_,Option<f64>>(2)?,"localArea":row.get::<_,Option<String>>(3)?,"municipalUnitId":row.get::<_,Option<i64>>(4)?,"communityId":row.get::<_,Option<i64>>(5)?,"municipalityId":row.get::<_,Option<i64>>(6)?}),
    )
}
fn not_evaluated(input: &impl serde::Serialize, reason: &str) -> Value {
    json!({"status":"not_evaluated","input":input,"reason":reason})
}
fn normalize(value: &str) -> String {
    value
        .nfd()
        .filter(|character| !matches!(character, '\u{301}' | '\u{308}'))
        .flat_map(char::to_lowercase)
        .filter(|character| character.is_alphanumeric())
        .map(|character| if character == 'ς' { 'σ' } else { character })
        .collect()
}
fn contains_house_number(street: &Value, number: i64) -> Option<bool> {
    let (start_key, end_key) = if number % 2 == 1 {
        ("oddStart", "oddEnd")
    } else {
        ("evenStart", "evenEnd")
    };
    let start = range_number(street[start_key].as_str())?;
    let end_text = street[end_key].as_str().unwrap_or("");
    let end = range_number(Some(end_text));
    if end.is_none() && normalize(end_text) != "τελ" {
        return None;
    }
    Some(number >= start && (normalize(end_text) == "τελ" || number <= end.unwrap()))
}
fn range_number(value: Option<&str>) -> Option<i64> {
    value?
        .trim_start()
        .split(|character: char| !character.is_ascii_digit())
        .next()?
        .parse()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contract() -> Result<()> {
        let client = PostalCodeClient::new()?;
        assert_eq!(client.list_regions(ListOptions::default())?.len(), 13);
        assert_eq!(
            client.search_regions("Αττικης", ListOptions::default())?[0]["name"],
            "Αττικής"
        );
        let postcode = client
            .get_postcode(
                "10431",
                PostcodeOptions {
                    include_hierarchy: true,
                    include_streets: true,
                },
            )?
            .unwrap();
        assert_eq!(postcode["hierarchy"]["municipality"]["name"], "Αθηναίων");
        assert!(
            postcode["streets"]
                .as_array()
                .unwrap()
                .iter()
                .any(|street| street["name"] == "Αγίου Κωνσταντίνου")
        );
        Ok(())
    }
}
