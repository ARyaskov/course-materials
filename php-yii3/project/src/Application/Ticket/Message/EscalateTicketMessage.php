<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

use Yiisoft\Queue\Message\Message;

// Версия в самом сообщении: старый обработчик поймёт, что не умеет его разбирать
final class EscalateTicketMessage extends Message
{
    public const TYPE = 'ticket.escalate';
    public const VERSION = 2;

    public function __construct(
        public readonly int $ticketId,
        public readonly string $reason,
        public readonly int $version = self::VERSION,
    ) {
    }

    public function getType(): string
    {
        return self::TYPE;
    }

    public function getPayload(): array
    {
        return [
            'ticketId' => $this->ticketId,
            'reason' => $this->reason,
            'version' => $this->version,
        ];
    }
}
