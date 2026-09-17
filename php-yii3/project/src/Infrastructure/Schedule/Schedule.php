<?php

declare(strict_types=1);

namespace App\Infrastructure\Schedule;

/**
 * Собрано из фрагмента урока 16.6: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class Schedule
{
    /**
     * Блокировка через атомарную операцию кеша. TTL страхует от
     * вечной блокировки, если процесс умер, не сняв её.
     */
    public function acquireLock(ScheduledTask $task): bool
    {
        return $this->cache->add(
            'schedule:lock:' . $task->name,
            (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM),
            ttl: $task->maxRuntimeSeconds,
        );
    }

    public function releaseLock(ScheduledTask $task): void
    {
        $this->cache->delete('schedule:lock:' . $task->name);
    }
}
