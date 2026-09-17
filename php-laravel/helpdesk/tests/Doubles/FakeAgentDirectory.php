<?php
// tests/Doubles/FakeAgentDirectory.php
declare(strict_types=1);

namespace Tests\Doubles;

use App\Contracts\AgentDirectory;
use App\DTO\AgentInfo;

final class FakeAgentDirectory implements AgentDirectory
{
    /** @param  array<int, AgentInfo>  $agents */
    public function __construct(private array $agents = [])
    {
    }

    public function find(int $userId): ?AgentInfo
    {
        return $this->agents[$userId] ?? null;
    }

    public function byDepartment(string $department): array
    {
        return array_values(array_filter(
            $this->agents,
            fn (AgentInfo $a): bool => $a->department === $department,
        ));
    }
}
