<?php
// app/Contracts/AgentDirectory.php
declare(strict_types=1);

namespace App\Contracts;

use App\DTO\AgentInfo;

interface AgentDirectory
{
    public function find(int $userId): ?AgentInfo;

    /** @return list<AgentInfo> */
    public function byDepartment(string $department): array;
}
