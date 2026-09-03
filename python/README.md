# Greek Postal Code DB for Python

Offline, read-only Greek postal-code data using Python's standard-library SQLite support. The database is included as package data.

This library lives in the `python/` subdirectory of a monorepo. Until it is published on PyPI, install it directly with:

```bash
pip install "git+https://github.com/rallisf1/greek-postal-code-db.git#subdirectory=python"
```

```python
from greek_postal_code_db import create_postal_code_client

with create_postal_code_client() as client:
    postcode = client.get_postcode("10431", include_hierarchy=True, include_streets=True)
    municipalities = client.search_municipalities("Αθην", include_hierarchy=True)
```

The client exposes `list_regions`, `list_regional_units`, `list_municipalities`, `list_municipal_units`, `list_communities`, the five matching `search_…` methods, `get_postcode`, `validate_address`, and `close`.

Entity methods accept keyword options for their parent ID, `limit`, `include_hierarchy`, and (except regions) `include_official_code`. `get_postcode` accepts `include_hierarchy` and `include_streets`. `validate_address` reports every supplied component independently as `valid`, `invalid`, or `not_evaluated`.
