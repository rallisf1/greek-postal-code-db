<?php

declare(strict_types=1);

namespace Rallisf1\GreekPostalCodeDb\Tests;

use PHPUnit\Framework\TestCase;
use Rallisf1\GreekPostalCodeDb\PostalCodeClient;
use RuntimeException;

final class PostalCodeClientTest extends TestCase
{
    public function testListsSearchesAndIncludesHierarchy(): void
    {
        $client = new PostalCodeClient();
        try {
            self::assertCount(13, $client->listRegions());
            self::assertSame('Αττικής', $client->searchRegions('Αττικης')[0]['name']);
            $municipality = $client->searchMunicipalities('Αθην', ['include' => ['hierarchy' => true]])[0];
            self::assertSame('Κεντρικού Τομέα Αθηνών', $municipality['hierarchy']['regionalUnit']['name']);
        } finally {
            $client->close();
        }
    }

    public function testLooksUpPostcodesAndValidatesAddresses(): void
    {
        $client = new PostalCodeClient();
        try {
            $postcode = $client->getPostcode('10431', ['include' => ['hierarchy' => true, 'streets' => true]]);
            self::assertSame('Αθηναίων', $postcode['hierarchy']['municipality']['name']);
            self::assertContains('Αγίου Κωνσταντίνου', array_column($postcode['streets'], 'name'));
            $validation = $client->validateAddress(['postcode' => '10431', 'street' => 'Βενιζέλου Ελευθερίου', 'houseNumber' => 69, 'municipality' => 'Αθην']);
            self::assertSame('valid', $validation['postcode']['status']);
            self::assertSame('valid', $validation['houseNumber']['status']);
            self::assertSame('valid', $validation['municipality']['status']);
        } finally {
            $client->close();
        }
    }

    public function testClosingPreventsFurtherQueries(): void
    {
        $client = new PostalCodeClient();
        $client->close();
        $this->expectException(RuntimeException::class);
        $client->listRegions();
    }
}
