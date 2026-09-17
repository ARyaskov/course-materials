<?php
// app/Support/Pipeline.php
declare(strict_types=1);

namespace App\Support;

use Closure;

final class Pipeline
{
    /** @var list<Closure(mixed): mixed> */
    private array $stages = [];

    public function pipe(Closure ...$stages): static
    {
        foreach ($stages as $stage) {
            $this->stages[] = $stage;
        }

        return $this;
    }

    public function process(mixed $payload): mixed
    {
        foreach ($this->stages as $stage) {
            $payload = $stage($payload);
        }

        return $payload;
    }
}

$clean = new Pipeline()
    ->pipe(trim(...), mb_strtolower(...), ucfirst(...))
    ->process('  НЕ РАБОТАЕТ VPN  ');

echo $clean;   // Не работает vpn
