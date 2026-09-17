<?php

declare(strict_types=1);

namespace App\Domain\Directory;

interface DirectoryClientInterface
{
    /** @throws Exception\DirectoryUnavailableException */
    public function findByEmail(string $email): ?Employee;

    /**
     * Пакетный запрос: одно обращение вместо N.
     *
     * @param list<string> $emails
     * @return array<string, Employee> ключ — e-mail
     * @throws Exception\DirectoryUnavailableException
     */
    public function findManyByEmail(array $emails): array;
}
