<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Application\Ticket\Message\TicketClosedMessage;
use App\Domain\Comment\{Comment, CommentRepositoryInterface};
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\{Ticket, TicketId, TicketRepositoryInterface, TicketStatus};
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Queue\QueueInterface;

final readonly class CloseTicketService
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
        // граница транзакции — сценарий: он знает, что образует единое целое
        $ticket = $this->db->transaction(
            function () use ($id, $resolution, $actorId): Ticket {
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
            },
        );

        // ВНЕ транзакции: воркер не должен забрать сообщение до COMMIT
        foreach ($ticket->releaseEvents() as $event) {
            $this->queue->push(TicketClosedMessage::fromEvent($event));
        }

        return $ticket;
    }
}
