<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

use App\Application\Ticket\EscalateTicketService;
use Psr\Log\LoggerInterface;
use Yiisoft\Queue\Message\MessageInterface;

final readonly class EscalateTicketHandler
{
    public function __construct(
        private EscalateTicketService $service,
        private LoggerInterface $logger,
    ) {
    }

    public function handle(MessageInterface $message): void
    {
        $payload = $message->getPayload();
        $version = (int) ($payload['version'] ?? 1);

        if ($version > EscalateTicketMessage::VERSION) {
            // сообщение из будущего: поставлено новым кодом, разбирается старым
            $this->logger->warning('Сообщение новее обработчика, откладываем', [
                'type' => $message->getType(),
                'messageVersion' => $version,
                'handlerVersion' => EscalateTicketMessage::VERSION,
            ]);

            throw new \RuntimeException('Version mismatch: требуется перевыкатка');
        }

        $this->service->escalate((int) $payload['ticketId'], (string) $payload['reason']);
    }
}
