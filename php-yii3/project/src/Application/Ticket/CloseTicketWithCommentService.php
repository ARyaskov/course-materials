<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Comment\{Comment, CommentRepositoryInterface};
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\{Ticket, TicketId, TicketRepositoryInterface, TicketStatus};
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Queue\QueueInterface;

final readonly class CloseTicketWithCommentService
{
    public function __construct(
        private ConnectionInterface $db,
        private TicketRepositoryInterface $tickets,
        private CommentRepositoryInterface $comments,
        private QueueInterface $queue,
    ) {
    }

    public function close(TicketId $id, string $resolution, int $actorId): Ticket
    {
        // обе записи применяются целиком или не применяются вовсе
        $ticket = $this->db->transaction(function () use ($id, $resolution, $actorId): Ticket {
            $ticket = $this->tickets->findById($id)
                ?? throw TicketNotFoundException::withId($id);

            $ticket->changeStatus(TicketStatus::Closed, $actorId);
            $this->tickets->save($ticket);

            $this->comments->save(Comment::create(
                ticketId: $ticket->id,
                authorId: $actorId,
                body: $resolution,
            ));

            return $ticket;
        });

        // очередь — ЗА пределами транзакции: см. урок о фоновых задачах
        foreach ($ticket->releaseEvents() as $event) {
            $this->queue->push(TicketClosedMessage::fromEvent($event));
        }

        return $ticket;
    }
}
