<?php
// app/Support/Concerns/Cacheable.php
declare(strict_types=1);

namespace App\Support\Concerns;

use Illuminate\Support\Facades\Cache;

trait Cacheable
{
    abstract protected function cacheKey(): string;

    abstract protected function cacheTtl(): int;

    protected function remember(\Closure $callback): mixed
    {
        return Cache::remember($this->cacheKey(), $this->cacheTtl(), $callback);
    }

    protected function forgetCache(): void
    {
        Cache::forget($this->cacheKey());
    }
}
