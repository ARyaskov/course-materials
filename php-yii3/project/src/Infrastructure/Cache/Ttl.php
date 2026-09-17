<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

final class Ttl
{
    /** Разброс ±10 %: ключи истекают не разом. */
    public static function jittered(int $seconds, float $spread = 0.1): int
    {
        $delta = (int) ($seconds * $spread);

        return $seconds + random_int(-$delta, $delta);
    }
}
