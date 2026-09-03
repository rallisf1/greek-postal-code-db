<?php

declare(strict_types=1);

$source = dirname(__DIR__, 2) . '/library.sqlite';
$targetDirectory = dirname(__DIR__) . '/data';
$target = $targetDirectory . '/library.sqlite';

if (!is_file($source)) {
    fwrite(STDERR, "Canonical database not found: {$source}\n");
    exit(1);
}
if (!is_dir($targetDirectory) && !mkdir($targetDirectory, 0777, true) && !is_dir($targetDirectory)) {
    fwrite(STDERR, "Unable to create {$targetDirectory}\n");
    exit(1);
}
if (!copy($source, $target)) {
    fwrite(STDERR, "Unable to copy {$source} to {$target}\n");
    exit(1);
}
