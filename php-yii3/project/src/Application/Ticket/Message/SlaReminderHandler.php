<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

use App\Domain\Ticket\{TicketId, TicketRepositoryInterface};
use App\Infrastructure\Mail\MailerInterface;
use Psr\SimpleCache\CacheInterface;
use Yiisoft\Queue\Message\MessageInterface;

final readonly class SlaReminderHandler
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private MailerInterface $mailer,
        private CacheInterface $cache,
    ) {
    }

    public function handle(MessageInterface $message): void
    {
        $ticketId = (int) $message->getPayload()['ticketId'];
        $ticket = $this->tickets->findById(TicketId::fromInt($ticketId));

        // объект удалён или уже закрыт — не ошибка, просто нечего делать
        if ($ticket === null || !$ticket->status->isActive() || $ticket->slaDeadline === null) {
            return;
        }

        // ключ включает СРОК, а не только идентификатор: при смене приоритета
        // срок меняется, и новое напоминание отправится законно
        $key = sprintf('sla-reminder:%d:%s', $ticketId,
            $ticket->slaDeadline->format('Y-m-d\TH:i'));

        if (!$this->cache->add($key, true, ttl: 86400)) {
            return;                       // про этот срок уже напоминали
        }

        try {
            $this->mailer->sendSlaReminder($ticket);
        } catch (\Throwable $e) {
            // снимаем отметку: иначе первая неудача навсегда пометит
            // напоминание как отправленное
            $this->cache->delete($key);

            throw $e;
        }
    }
}
