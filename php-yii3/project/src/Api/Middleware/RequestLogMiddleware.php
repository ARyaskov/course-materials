<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\Log\LoggerInterface;

final readonly class RequestLogMiddleware implements MiddlewareInterface
{
    public function __construct(private LoggerInterface $logger)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        // ДО: то, что известно из запроса, и то, что нужно зафиксировать
        // даже если ниже всё упадёт
        $startedAt = hrtime(true);
        $method = $request->getMethod();
        $path = $request->getUri()->getPath();

        try {
            $response = $handler->handle($request);
        } catch (\Throwable $e) {
            // запись о запросе должна появиться и при исключении
            $this->logger->error('Запрос завершился исключением', [
                'method' => $method,
                'path' => $path,
                'exception' => $e::class,
                'durationMs' => round((hrtime(true) - $startedAt) / 1_000_000, 1),
            ]);

            throw $e;                 // пробрасываем: ловить будет ErrorCatcher
        }

        // ПОСЛЕ: то, что известно только из ответа
        $this->logger->info('Запрос обработан', [
            'method' => $method,
            'path' => $path,
            'status' => $response->getStatusCode(),
            'durationMs' => round((hrtime(true) - $startedAt) / 1_000_000, 1),
        ]);

        return $response;
    }
}
