<?php

declare(strict_types=1);

namespace App\Infrastructure\Directory;

use App\Domain\Directory\{DirectoryClientInterface, Employee};

final readonly class CsvDirectoryClient implements DirectoryClientInterface
{
    public function __construct(private string $path)
    {
    }

    public function findByEmail(string $email): ?Employee
    {
        foreach ($this->rows() as $row) {
            if (strcasecmp($row['email'], $email) === 0) {
                return Employee::fromArray($row);
            }
        }

        return null;
    }

    public function findManyByEmail(array $emails): array
    {
        $wanted = array_map(strtolower(...), $emails);
        $result = [];

        foreach ($this->rows() as $row) {
            if (in_array(strtolower($row['email']), $wanted, true)) {
                $result[$row['email']] = Employee::fromArray($row);
            }
        }

        return $result;
    }

    /** @return iterable<array{email: string, name: string, department: string}> */
    private function rows(): iterable
    {
        $handle = fopen($this->path, 'rb')
            ?: throw new \RuntimeException("Не открыть {$this->path}");

        try {
            $header = fgetcsv($handle);

            while (($row = fgetcsv($handle)) !== false) {
                yield array_combine($header, $row);
            }
        } finally {
            fclose($handle);
        }
    }
}
