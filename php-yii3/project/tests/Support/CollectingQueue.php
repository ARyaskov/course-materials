<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Yiisoft\Queue\Message\MessageInterface;
use Yiisoft\Queue\QueueInterface;

final class CollectingQueue implements QueueInterface
{
    /** @var list<MessageInterface> */
    private array $messages = [];

    public function push(
        MessageInterface $message,
        MiddlewareInterface|callable|array|string ...$middlewareDefinitions,
    ): MessageInterface {
        $this->messages[] = $message;

        return $message;
    }

    /** @return list<MessageInterface> */
    public function messages(): array
    {
        return $this->messages;
    }

    /** @return list<MessageInterface> */
    public function messagesOfType(string $type): array
    {
        return array_values(
            array_filter($this->messages, static fn (MessageInterface $m): bool
                => $m->getType() === $type),
        );
    }

    // остальные методы QueueInterface в тестах не нужны
    public function status(string|int $id): JobStatus
    {
        throw new \LogicException('Не используется в тестах');
    }
}
