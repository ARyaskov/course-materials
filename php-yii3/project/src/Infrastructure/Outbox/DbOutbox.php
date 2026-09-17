<?php

declare(strict_types=1);

namespace App\Infrastructure\Outbox;

use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Queue\Message\MessageInterface;

final readonly class DbOutbox
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    /** Вызывается ВНУТРИ транзакции: запись фиксируется вместе с данными. */
    public function put(MessageInterface $message): void
    {
        $this->db->createCommand()->insert('{{%outbox}}', [
            'type' => $message->getType(),
            'payload' => json_encode($message->getPayload(), JSON_THROW_ON_ERROR),
            'created_at' => (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM),
        ])->execute();
    }
}
