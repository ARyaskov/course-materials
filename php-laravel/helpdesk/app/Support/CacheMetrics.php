<?php
// app/Support/CacheMetrics.php
declare(strict_types=1);

namespace App\Support;

use Illuminate\Cache\Events\CacheHit;
use Illuminate\Cache\Events\CacheMissed;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Redis;

final class CacheMetrics
{
    public static function register(): void
    {
        Event::listen(CacheHit::class, function (CacheHit $event): void {
            Redis::connection('cache')->hincrby('cache:metrics', self::group($event->key) . ':hit', 1);
        });

        Event::listen(CacheMissed::class, function (CacheMissed $event): void {
            Redis::connection('cache')->hincrby('cache:metrics', self::group($event->key) . ':miss', 1);
        });
    }

    private static function group(string $key): string
    {
        // stats:user:7 → stats:user
        return preg_replace('/:\d+$/', '', $key) ?? $key;
    }
}
