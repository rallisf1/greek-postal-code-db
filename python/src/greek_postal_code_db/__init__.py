"""Offline, read-only Greek postal-code data."""

from .client import PostalCodeClient, create_postal_code_client

__all__ = ["PostalCodeClient", "create_postal_code_client"]
