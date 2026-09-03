import unittest

from greek_postal_code_db import create_postal_code_client


class PostalCodeClientTest(unittest.TestCase):
    def setUp(self):
        self.client = create_postal_code_client()

    def tearDown(self):
        self.client.close()

    def test_lists_searches_and_hierarchy(self):
        self.assertEqual(13, len(self.client.list_regions()))
        self.assertEqual("Αττικής", self.client.search_regions("Αττικης")[0]["name"])
        municipality = self.client.search_municipalities("Αθην", include_hierarchy=True)[0]
        self.assertEqual("Κεντρικού Τομέα Αθηνών", municipality["hierarchy"]["regionalUnit"]["name"])

    def test_postcode_and_validation(self):
        postcode = self.client.get_postcode("10431", include_hierarchy=True, include_streets=True)
        self.assertEqual("Αθηναίων", postcode["hierarchy"]["municipality"]["name"])
        self.assertIn("Αγίου Κωνσταντίνου", [street["name"] for street in postcode["streets"]])
        valid = self.client.validate_address("10431", street="Βενιζέλου Ελευθερίου", house_number=69, municipality="Αθην")
        self.assertEqual("valid", valid["postcode"]["status"])
        self.assertEqual("valid", valid["houseNumber"]["status"])
        self.assertEqual("valid", valid["municipality"]["status"])

    def test_close_prevents_queries(self):
        self.client.close()
        with self.assertRaisesRegex(RuntimeError, "closed"):
            self.client.list_regions()
