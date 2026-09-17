<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

/**
 * Собрано из фрагмента урока 16.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class CloseStaleTicketHandler
{
    public function handle(MessageInterface $message): void
    {
        $ticket = $this->tickets->findById(
            TicketId::fromInt((int) $message->getPayload()['ticketId']),
        );

        if ($ticket === null) {
            return;                              // удалена — нечего делать
        }

        // повторная обработка не изменит уже закрытую заявку
        if ($ticket->status->isFinal()) {
            return;
        }

        $this->statusService->changeStatus($ticket->id, TicketStatus::Closed, actorId: 0);
    }
}
