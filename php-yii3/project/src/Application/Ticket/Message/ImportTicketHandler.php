<?php

declare(strict_types=1);

namespace App\Application\Ticket\Message;

/**
 * Собрано из фрагмента урока 16.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class ImportTicketHandler
{
    public function handle(MessageInterface $message): void
    {
        $payload = $message->getPayload();

        try {
            $this->tickets->save(Ticket::importFrom(
                externalId: (string) $payload['externalId'],
                title: (string) $payload['title'],
                // ...
            ));
        } catch (IntegrityException $e) {
            // UNIQUE (external_id) — повтор импорта не создаёт дубль
            $this->logger->info('Заявка уже импортирована', [
                'externalId' => $payload['externalId'],
            ]);
        }
    }
}
