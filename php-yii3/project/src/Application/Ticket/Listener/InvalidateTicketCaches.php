<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

/**
 * Собрано из фрагмента урока 17.2: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class InvalidateTicketCaches
{
    public function onAssigned(TicketAssigned $event): void
    {
        $this->safely(function () use ($event): void {
            $this->cache->delete(CacheKey::ticket($event->ticketId));

            // оба исполнителя: у прежнего заявка исчезла, у нового появилась
            if ($event->previousAssigneeId !== null) {
                $this->cache->invalidateTag('tickets:assignee:' . $event->previousAssigneeId->value);
            }

            $this->cache->invalidateTag('tickets:assignee:' . $event->assigneeId->value);
        });
    }

    /** Сбой инвалидации не должен ломать основное действие: данные протухнут по TTL. */
    private function safely(callable $action): void
    {
        try {
            $action();
        } catch (\Throwable $e) {
            $this->logger->warning('Инвалидация кеша не удалась', ['reason' => $e->getMessage()]);
        }
    }
}
