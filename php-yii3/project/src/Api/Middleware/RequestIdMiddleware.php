<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\Log\LoggerInterface;

final readonly class RequestIdMiddleware implements MiddlewareInterface
{
    public const ATTRIBUTE = 'requestId';

    public function __construct(
        private LoggerInterface $logger,
        private RequestContext $context,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        // уважаем идентификатор от вышестоящего сервиса, если он пришёл
        $requestId = $request->getHeaderLine('X-Request-Id') ?: $this->generateId();

        $this->context->setRequestId($requestId);

        $startedAt = hrtime(true);
        $response = $handler->handle($request->withAttribute(self::ATTRIBUTE, $requestId));
        $durationMs = round((hrtime(true) - $startedAt) / 1_000_000, 1);

        $this->logger->info('HTTP-запрос обработан', [
            'method' => $request->getMethod(),
            'path' => $request->getUri()->getPath(),
            'status' => $response->getStatusCode(),
            'durationMs' => $durationMs,
        ]);

        // клиент сообщит этот id в обращении — по нему находится весь путь
        return $response->withHeader('X-Request-Id', $requestId);
    }

    private function generateId(): string
    {
        return bin2hex(random_bytes(8));
    }
}
