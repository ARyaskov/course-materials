<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\Ticket;
use App\Domain\Ticket\TicketRepositoryInterface;
use App\Application\Ticket\Message\SlaReminderMessage;
use App\Infrastructure\Config\FeatureFlags;
use Psr\Clock\ClockInterface;
use Yiisoft\Queue\Adapter\DelayMiddleware;
use Yiisoft\Queue\QueueInterface;

/**
 * Собрано из фрагментов уроков 16.3 и 19.7: в уроках показаны постановка
 * отложенного напоминания и обход эскалации по флагу.
 */
final readonly class EscalateTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private QueueInterface $queue,
        private FeatureFlags $features,
        private ClockInterface $clock,
    ) {
    }

    public function escalateOverdue(): int
    {
        if (!$this->features->enabled('sla-autoescalation')) {
            return 0;                       // новый путь выключен, старый не затронут
        }

        $escalated = 0;

        foreach ($this->tickets->findOverdue() as $ticket) {
            $this->escalate($ticket);
            $escalated++;
        }

        return $escalated;
    }

    public function escalate(Ticket $ticket): void
    {
        $secondsUntilReminder = max(
            0,
            ($ticket->slaDeadline?->getTimestamp() ?? 0) - $this->clock->now()->getTimestamp() - 3600,
        );

        // отправить напоминание за час до истечения SLA
        $this->queue->push(
            new SlaReminderMessage($ticket->id->value),
            // middleware push-стадии: задержка перед доставкой
            new DelayMiddleware($secondsUntilReminder),
        );
    }
}
