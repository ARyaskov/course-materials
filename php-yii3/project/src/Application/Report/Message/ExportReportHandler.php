<?php

declare(strict_types=1);

namespace App\Application\Report\Message;

/**
 * Собрано из фрагмента урока 16.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class ExportReportHandler
{
    public function handle(MessageInterface $message): void
    {
        $payload = $message->getPayload();

        // структура сообщения не изменится от повтора
        if (!isset($payload['exportId'], $payload['filter'])) {
            throw NonRetryableException::invalidPayload(
                $message->getType(), 'отсутствуют обязательные поля',
            );
        }

        try {
            $this->exporter->export((string) $payload['exportId'], (array) $payload['filter']);
        } catch (StorageUnavailableException $e) {
            // хранилище может подняться — пусть повторяется
            throw $e;
        }
    }
}
