<?php
// app/Support/CircuitBreaker.php
declare(strict_types=1);

namespace App\Support;

use App\Exceptions\ExternalServiceUnavailableException;
use Closure;
use Illuminate\Support\Facades\Cache;

final readonly class CircuitBreaker
{
    public function __construct(
        private string $service,
        private int $threshold = 5,
        private int $cooldownSeconds = 60,
    ) {
    }

    /**
     * @template T
     * @param  Closure(): T  $operation
     * @return T
     */
    public function call(Closure $operation): mixed
    {
        if ($this->isOpen()) {
            throw new ExternalServiceUnavailableException($this->service);
        }

        try {
            $result = $operation();

            $this->recordSuccess();

            return $result;
        } catch (\Throwable $e) {
            $this->recordFailure();

            throw $e;
        }
    }

    public function isOpen(): bool
    {
        return $this->failures() >= $this->threshold;
    }

    public function failures(): int
    {
        return (int) Cache::get($this->key(), 0);
    }

    private function recordFailure(): void
    {
        $failures = $this->failures() + 1;

        Cache::put($this->key(), $failures, $this->cooldownSeconds);

        if ($failures === $this->threshold) {
            logger()->channel('integrations')->error('circuit.opened', [
                'service'  => $this->service,
                'cooldown' => $this->cooldownSeconds,
            ]);
        }
    }

    private function recordSuccess(): void
    {
        if ($this->failures() > 0) {
            Cache::forget($this->key());

            logger()->channel('integrations')->info('circuit.closed', ['service' => $this->service]);
        }
    }

    private function key(): string
    {
        return "circuit:{$this->service}";
    }
}
