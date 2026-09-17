<?php
// app/Contracts/SearchIndex.php
declare(strict_types=1);

namespace App\Contracts;

interface SearchIndex
{
    public function index(int $ticketId, string $subject, string $body): void;

    /** @return list<int> */
    public function search(string $query, int $limit = 50): array;

    public function remove(int $ticketId): void;
}
