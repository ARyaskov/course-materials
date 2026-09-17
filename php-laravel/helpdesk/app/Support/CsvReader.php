<?php
// app/Support/CsvReader.php
declare(strict_types=1);

namespace App\Support;

use Generator;
use RuntimeException;

final readonly class CsvReader
{
    public function __construct(
        private string $path,
        private string $separator = ',',
    ) {
    }

    /** @return Generator<int, array<string, string>> */
    public function rows(): Generator
    {
        $handle = fopen($this->path, 'rb');

        if ($handle === false) {
            throw new RuntimeException("Не удалось открыть {$this->path}");
        }

        try {
            $header = fgetcsv($handle, separator: $this->separator);

            if ($header === false) {
                return;
            }

            $line = 1;

            while (($row = fgetcsv($handle, separator: $this->separator)) !== false) {
                $line++;

                if (count($row) !== count($header)) {
                    throw new RuntimeException("Строка {$line}: неверное число колонок");
                }

                yield $line => array_combine($header, $row);
            }
        } finally {
            fclose($handle);
        }
    }
}
