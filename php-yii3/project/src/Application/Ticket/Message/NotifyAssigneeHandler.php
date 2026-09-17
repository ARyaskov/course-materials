<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

use App\Domain\Ticket\{TicketId, TicketRepositoryInterface};
use App\Domain\User\{UserId, UserRepositoryInterface};
use App\Infrastructure\Mail\MailerInterface;
use Psr\Log\LoggerInterface;
use Yiisoft\Queue\Message\MessageInterface;

final readonly class NotifyAssigneeHandler
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private UserRepositoryInterface $users,
        private MailerInterface $mailer,
        private LoggerInterface $logger,
    ) {
    }

    public function handle(MessageInterface $message): void
    {
        $payload = $message->getPayload();

        // читаем АКТУАЛЬНОЕ состояние, а не то, что было при постановке
        $ticket = $this->tickets->findById(TicketId::fromInt((int) $payload['ticketId']));
        $assignee = $this->users->findById(UserId::fromInt((int) $payload['assigneeId']));

        if ($ticket === null || $assignee === null) {
            // объект удалён, пока сообщение ждало — это не ошибка.
            // Исключение здесь отправило бы сообщение в бесконечные повторы.
            $this->logger->info('Уведомление пропущено: объект не найден', $payload);

            return;
        }

        // состояние изменилось — уведомление потеряло смысл
        if (!$assignee->id->equals($ticket->assigneeId)) {
            $this->logger->info('Исполнитель уже сменился, уведомление пропущено', [
                'ticketId' => $ticket->id->value,
            ]);

            return;
        }

        $this->mailer->sendAssigned($ticket, $assignee);
    }
}
