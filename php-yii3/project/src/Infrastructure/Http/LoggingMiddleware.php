<?php

declare(strict_types=1);

namespace App\Infrastructure\Http;

use Psr\Http\Message\RequestInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Log\LoggerInterface;

final readonly class LoggingMiddleware
{
    public function __construct(private LoggerInterface $logger)
    {
    }

    public function __invoke(callable $handler): callable
    {
        return function (RequestInterface $request, array $options) use ($handler) {
            $startedAt = hrtime(true);

            return $handler($request, $options)->then(
                function (ResponseInterface $response) use ($request, $startedAt) {
                    $this->log($request, $response->getStatusCode(), $startedAt);

                    return $response;
                },
                function ($reason) use ($request, $startedAt) {
                    $this->log($request, 0, $startedAt);

                    return \GuzzleHttp\Promise\Create::rejectionFor($reason);
                },
            );
        };
    }

    private function log(RequestInterface $request, int $status, float $startedAt): void
    {
        $this->logger->info('Внешний вызов', [
            'host' => $request->getUri()->getHost(),
            'path' => $request->getUri()->getPath(),
            'method' => $request->getMethod(),
            'status' => $status,                              // 0 — до ответа не дошло
            'durationMs' => round((hrtime(true) - $startedAt) / 1_000_000, 1),
        ]);
    }
}
