<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

/**
 * Собрано из фрагмента урока 17.1: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class MeasuredCache
{
    public function get(string $key, mixed $default = null): mixed
    {
        $value = $this->inner->get($key, $default);

        // метки низкой кардинальности: префикс ключа, а не сам ключ
        $this->metrics->increment('cache_requests_total', [
            'prefix' => explode(':', $key)[0],
            'result' => $value === $default ? 'miss' : 'hit',
        ]);

        return $value;
    }
}
