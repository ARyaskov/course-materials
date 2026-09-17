<?php

declare(strict_types=1);

namespace App\Infrastructure\Log;

use Psr\Log\LoggerInterface;
use Psr\Log\LoggerTrait;

final class ContextualLogger implements LoggerInterface
{
    use LoggerTrait;

    public function __construct(
        private readonly LoggerInterface $inner,
        private readonly RequestContext $context,
    ) {
    }

    public function log($level, string|\Stringable $message, array $context = []): void
    {
        // requestId добавляется автоматически к каждой записи
        $this->inner->log($level, $message, [
            'requestId' => $this->context->requestId(),
            ...$context,
        ]);
    }
}
