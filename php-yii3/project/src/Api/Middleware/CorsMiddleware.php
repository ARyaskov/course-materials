<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\Http\Method;
use Yiisoft\Http\Status;

final readonly class CorsMiddleware implements MiddlewareInterface
{
    /** @param list<string> $allowedOrigins */
    public function __construct(
        private ResponseFactoryInterface $responseFactory,
        private array $allowedOrigins,
        private int $maxAge = 600,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $origin = $request->getHeaderLine('Origin');

        // не браузер — CORS неприменим, пропускаем без изменений
        if ($origin === '') {
            return $handler->handle($request);
        }

        $allowed = in_array($origin, $this->allowedOrigins, true);

        if ($this->isPreflight($request)) {
            // РЕЖИМ 1: отвечаем сами, $handler не вызывается вовсе
            return $this->preflightResponse($origin, $allowed);
        }

        // РЕЖИМ 2: пропускаем дальше и дописываем заголовки на пути наружу
        $response = $handler->handle($request);

        return $allowed
            ? $this->withCorsHeaders($response, $origin)
            : $response->withHeader('Vary', 'Origin');
    }

    private function isPreflight(ServerRequestInterface $request): bool
    {
        return $request->getMethod() === Method::OPTIONS
            && $request->hasHeader('Access-Control-Request-Method');
    }

    private function preflightResponse(string $origin, bool $allowed): ResponseInterface
    {
        $response = $this->responseFactory->createResponse(Status::NO_CONTENT);

        if (!$allowed) {
            // без разрешающих заголовков браузер сам заблокирует основной запрос
            return $response->withHeader('Vary', 'Origin');
        }

        return $this->withCorsHeaders($response, $origin)
            ->withHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS')
            ->withHeader('Access-Control-Allow-Headers',
                'Authorization, Content-Type, Idempotency-Key, X-Request-Id')
            ->withHeader('Access-Control-Max-Age', (string) $this->maxAge);
    }

    private function withCorsHeaders(ResponseInterface $response, string $origin): ResponseInterface
    {
        return $response
            ->withHeader('Access-Control-Allow-Origin', $origin)
            // без этого заголовка клиентский скрипт не увидит наши служебные
            ->withHeader('Access-Control-Expose-Headers', 'X-Request-Id, X-Total-Count')
            ->withHeader('Vary', 'Origin');
    }
}
