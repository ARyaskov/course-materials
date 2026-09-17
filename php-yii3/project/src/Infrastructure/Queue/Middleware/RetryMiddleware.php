<?php

declare(strict_types=1);

namespace App\Infrastructure\Queue\Middleware;

use App\Application\Queue\Exception\NonRetryableException;
use Psr\Log\LoggerInterface;
use Yiisoft\Queue\Middleware\FailureHandling\{FailureHandlingRequest,
    MessageFailureHandlerInterface, MiddlewareFailureInterface};

final readonly class RetryMiddleware implements MiddlewareFailureInterface
{
    private const MAX_ATTEMPTS = 5;

    public function __construct(
        private LoggerInterface $logger,
        private FailedMessageStorage $failed,
    ) {
    }

    public function processFailure(
        FailureHandlingRequest $request,
        MessageFailureHandlerInterface $handler,
    ): FailureHandlingRequest {
        $message = $request->getMessage();
        $exception = $request->getException();
        $attempt = (int) ($message->getMetadata()['attempt'] ?? 0) + 1;

        // постоянный сбой — не повторяем вовсе
        if ($exception instanceof NonRetryableException) {
            $this->failed->store($message, $exception, $attempt);

            $this->logger->error('Сообщение отправлено в failed без повторов', [
                'type' => $message->getType(),
                'reason' => $exception->getMessage(),
            ]);

            return $request;
        }

        if ($attempt >= self::MAX_ATTEMPTS) {
            $this->failed->store($message, $exception, $attempt);

            // исчерпание попыток — событие, требующее внимания человека
            $this->logger->error('Исчерпаны попытки обработки', [
                'type' => $message->getType(),
                'attempts' => $attempt,
                'lastError' => $exception->getMessage(),
            ]);

            return $request;
        }

        $delay = $this->delayFor($attempt);

        $this->logger->warning('Повтор обработки сообщения', [
            'type' => $message->getType(),
            'attempt' => $attempt,
            'delaySeconds' => $delay,
        ]);

        return $handler->handleFailure($request->withMessage(
            $message->withMetadata(['attempt' => $attempt, 'delay' => $delay]),
        ));
    }

    /** Экспоненциальная задержка с джиттером: 1, 2, 4, 8, 16 минут ± разброс. */
    private function delayFor(int $attempt): int
    {
        $base = 60 * (2 ** ($attempt - 1));

        return $base + random_int(0, (int) ($base * 0.25));
    }
}
