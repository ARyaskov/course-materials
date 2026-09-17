<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

use App\Domain\Ticket\Event\TicketAssigned;
use Yiisoft\Queue\Message\Message;

final class NotifyAssigneeMessage extends Message
{
    // константа, а не строка по коду: опечатка станет ошибкой анализатора
    public const TYPE = 'ticket.notify-assignee';

    public function __construct(
        public readonly int $ticketId,
        public readonly int $assigneeId,
        public readonly ?string $requestId = null,
    ) {
    }

    public function getType(): string
    {
        return self::TYPE;
    }

    /** Payload сериализуется в хранилище — только скаляры и массивы. */
    public function getPayload(): array
    {
        return [
            'ticketId' => $this->ticketId,
            'assigneeId' => $this->assigneeId,
        ];
    }

    /** Метаданные не относятся к работе, но нужны для наблюдения. */
    public function getMetadata(): array
    {
        return [
            'requestId' => $this->requestId,
            'pushedAt' => (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM),
        ];
    }

    public static function fromEvent(TicketAssigned $event, ?string $requestId = null): self
    {
        return new self(
            ticketId: $event->ticketId->value,
            assigneeId: $event->assigneeId->value,
            requestId: $requestId,
        );
    }
}
