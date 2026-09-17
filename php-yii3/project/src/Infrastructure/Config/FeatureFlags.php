<?php

declare(strict_types=1);

namespace App\Infrastructure\Config;

final readonly class FeatureFlags
{
    /** @param array<string, bool> $flags */
    public function __construct(private array $flags)
    {
    }

    public function enabled(string $feature): bool
    {
        return $this->flags[$feature] ?? false;
    }
}
