<?php
// app/DTO/AgentInfo.php
declare(strict_types=1);

namespace App\DTO;

final readonly class AgentInfo
{
    public function __construct(
        public int $id,
        public string $name,
        public string $department,
        public bool $isActive,
    ) {
    }

    /** @param  array<string, mixed>  $data */
    public static function fromArray(array $data): self
    {
        return new self(
            id: (int) $data['id'],
            name: (string) $data['name'],
            department: (string) ($data['department'] ?? 'Не указан'),
            isActive: (bool) ($data['is_active'] ?? true),
        );
    }
}
